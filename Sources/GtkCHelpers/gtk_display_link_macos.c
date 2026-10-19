// GDK's display link on macOS, kept running while an animation is.
//
// See the declaration in include/gtk_helpers.h for why. GDK (4.24) stops its
// CVDisplayLink after every presented frame and starts it again from the next
// paint, and a CVDisplayLink started less than about 10 ms before a refresh
// gives its first callback one refresh later. This file replaces GDK's imports
// of CVDisplayLinkStart, CVDisplayLinkStop and CVDisplayLinkRelease (the slots
// in libgtk-4's __got, found by name through the indirect symbol table) with
// functions that leave a link running while scui_macos_display_link_keep_running
// is on, and stop it when it goes off or the link is released. GDK's own state
// is untouched: its source still ignores callbacks while GDK has it paused.
//
// macOS 上 GDK 的 display link,在動畫進行期間保持運轉。原因見 include/gtk_helpers.h 中的宣告。
// GDK(4.24)在每一幀呈現之後停掉它的 CVDisplayLink,並在下一次繪製時再啟動;而一個在更新前不到約
// 10 毫秒才啟動的 CVDisplayLink,第一次 callback 會晚一個更新週期。本檔把 GDK 對 CVDisplayLinkStart、
// CVDisplayLinkStop 與 CVDisplayLinkRelease 的引用(libgtk-4 的 __got 中的槽位，經由 indirect symbol
// table 依名稱找出)換成：在 scui_macos_display_link_keep_running 開啟期間讓 link 繼續運轉，並在它關閉
// 或 link 被釋放時停掉 link 的函式。GDK 自己的狀態不受影響:GDK 暫停它時，它的 source 仍會忽略 callback。

#include "include/gtk_helpers.h"

#if defined(__APPLE__) && defined(GDK_WINDOWING_MACOS)

#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <mach/mach.h>
#include <stdint.h>
#include <string.h>

typedef int32_t (*scui_cv_link_call)(void *link);

static scui_cv_link_call scui_real_start;
static scui_cv_link_call scui_real_stop;
static void (*scui_real_release)(void *link);

// GDK's links: whether GDK last asked for each to run, and whether it runs.
// GDK 的 link:GDK 最後一次是否要求它運轉，以及它是否正在運轉。
typedef struct {
    void *link;
    int wanted;
    int running;
} ScuiLinkState;

#define SCUI_MAX_LINKS 16
static ScuiLinkState scui_links[SCUI_MAX_LINKS];
static int scui_keep_running;

static ScuiLinkState *scui_link_state(void *link, int running_if_new) {
    ScuiLinkState *free_slot = NULL;
    for (int i = 0; i < SCUI_MAX_LINKS; i++) {
        if (scui_links[i].link == link) {
            return &scui_links[i];
        }
        if (scui_links[i].link == NULL && free_slot == NULL) {
            free_slot = &scui_links[i];
        }
    }
    if (free_slot == NULL) {
        return NULL;
    }
    free_slot->link = link;
    free_slot->wanted = running_if_new;
    free_slot->running = running_if_new;
    return free_slot;
}

static int32_t scui_link_start(void *link) {
    // A link GDK has not touched since this was installed is stopped:
    // GDK starts a link only when it is paused.
    // 安裝之後 GDK 尚未碰過的 link 是停著的:GDK 只在暫停時才啟動 link。
    ScuiLinkState *state = scui_link_state(link, 0);
    if (state == NULL) {
        return scui_real_start(link);
    }
    state->wanted = 1;
    if (state->running) {
        return 0;
    }
    int32_t result = scui_real_start(link);
    state->running = (result == 0);
    return result;
}

static int32_t scui_link_stop(void *link) {
    // GDK stops a link only while it runs. / GDK 只在 link 運轉時停掉它。
    ScuiLinkState *state = scui_link_state(link, 1);
    if (state == NULL) {
        return scui_real_stop(link);
    }
    state->wanted = 0;
    if (scui_keep_running || !state->running) {
        return 0;
    }
    state->running = 0;
    return scui_real_stop(link);
}

static void scui_link_release(void *link) {
    for (int i = 0; i < SCUI_MAX_LINKS; i++) {
        if (scui_links[i].link == link) {
            // Never release a link that still calls back into a freed source.
            // 絕不釋放一個仍會 callback 到已釋放 source 的 link。
            if (scui_links[i].running) {
                scui_real_stop(link);
            }
            scui_links[i].link = NULL;
        }
    }
    scui_real_release(link);
}

static void scui_replace_slot(void **slot, void *replacement, void **original, int read_only) {
    if (*slot == replacement) {
        return;
    }
    vm_address_t page = (vm_address_t)slot & ~(vm_address_t)(vm_page_size - 1);
    if (vm_protect(mach_task_self(), page, vm_page_size, 0,
                   VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY) != KERN_SUCCESS) {
        return;
    }
    if (*original == NULL) {
        *original = *slot;
    }
    *slot = replacement;
    if (read_only) {
        vm_protect(mach_task_self(), page, vm_page_size, 0, VM_PROT_READ);
    }
}

// Replaces the three imports in one image; returns how many slots changed.
// 在一個 image 中替換這三個引用;回傳改了幾個槽位。
static int scui_rebind_image(const struct mach_header_64 *header, intptr_t slide) {
    const struct segment_command_64 *linkedit = NULL;
    const struct symtab_command *symtab = NULL;
    const struct dysymtab_command *dysymtab = NULL;
    const struct load_command *command = (const void *)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++) {
        if (command->cmd == LC_SEGMENT_64 &&
            strcmp(((const struct segment_command_64 *)command)->segname, SEG_LINKEDIT) == 0) {
            linkedit = (const void *)command;
        } else if (command->cmd == LC_SYMTAB) {
            symtab = (const void *)command;
        } else if (command->cmd == LC_DYSYMTAB) {
            dysymtab = (const void *)command;
        }
        command = (const void *)((const char *)command + command->cmdsize);
    }
    if (linkedit == NULL || symtab == NULL || dysymtab == NULL || dysymtab->nindirectsyms == 0) {
        return 0;
    }
    uintptr_t base = (uintptr_t)slide + linkedit->vmaddr - linkedit->fileoff;
    const struct nlist_64 *symbols = (const void *)(base + symtab->symoff);
    const char *strings = (const char *)(base + symtab->stroff);
    const uint32_t *indirect = (const void *)(base + dysymtab->indirectsymoff);

    int replaced = 0;
    command = (const void *)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++) {
        if (command->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *segment = (const void *)command;
            const struct section_64 *section = (const void *)(segment + 1);
            int read_only = strcmp(segment->segname, "__DATA_CONST") == 0;
            for (uint32_t s = 0; s < segment->nsects; s++, section++) {
                uint32_t type = section->flags & SECTION_TYPE;
                if (type != S_NON_LAZY_SYMBOL_POINTERS && type != S_LAZY_SYMBOL_POINTERS) {
                    continue;
                }
                void **slots = (void **)((uintptr_t)slide + section->addr);
                const uint32_t *names = indirect + section->reserved1;
                for (uint64_t n = 0; n < section->size / sizeof(void *); n++) {
                    uint32_t index = names[n];
                    if (index & (INDIRECT_SYMBOL_ABS | INDIRECT_SYMBOL_LOCAL) || index >= symtab->nsyms) {
                        continue;
                    }
                    const char *name = strings + symbols[index].n_un.n_strx;
                    if (strcmp(name, "_CVDisplayLinkStart") == 0) {
                        scui_replace_slot(&slots[n], (void *)scui_link_start, (void **)&scui_real_start, read_only);
                        replaced++;
                    } else if (strcmp(name, "_CVDisplayLinkStop") == 0) {
                        scui_replace_slot(&slots[n], (void *)scui_link_stop, (void **)&scui_real_stop, read_only);
                        replaced++;
                    } else if (strcmp(name, "_CVDisplayLinkRelease") == 0) {
                        scui_replace_slot(&slots[n], (void *)scui_link_release, (void **)&scui_real_release, read_only);
                        replaced++;
                    }
                }
            }
        }
        command = (const void *)((const char *)command + command->cmdsize);
    }
    return replaced;
}

// 1 when all three of GDK's imports are replaced, -1 when they could not be.
// 三個 GDK 引用都已替換時為 1,無法替換時為 -1。
static int scui_installed;

static void scui_install(void) {
    if (scui_installed != 0) {
        return;
    }
    scui_installed = -1;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (name == NULL || strstr(name, "/libgtk-4") == NULL) {
            continue;
        }
        const struct mach_header_64 *header = (const void *)_dyld_get_image_header(i);
        if (header->magic != MH_MAGIC_64) {
            continue;
        }
        int replaced = scui_rebind_image(header, _dyld_get_image_vmaddr_slide(i));
        if (replaced >= 3 && scui_real_start && scui_real_stop && scui_real_release) {
            scui_installed = 1;
        }
    }
}

int scui_macos_display_link_keep_running(int keep) {
    scui_install();
    if (scui_installed != 1) {
        return 0;
    }
    scui_keep_running = keep;
    if (!keep) {
        for (int i = 0; i < SCUI_MAX_LINKS; i++) {
            if (scui_links[i].link && scui_links[i].running && !scui_links[i].wanted) {
                scui_links[i].running = 0;
                scui_real_stop(scui_links[i].link);
            }
        }
    }
    return 1;
}

#else

int scui_macos_display_link_keep_running(int keep) {
    (void)keep;
    return 0;
}

#endif
