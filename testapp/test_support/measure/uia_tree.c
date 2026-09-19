// uia_tree.c -- dump a window's UI Automation tree from OUTSIDE the process,
// through a named view (raw / control / content), so a reading says which tree
// it came from.
//
//   uia_tree.exe <title substring> raw|control|content
//
// It exists because the view went unnamed once and a correct reading was
// doubted. An earlier external UIA client listed `X` and `decorative` under
// P69-WinUI without saying which view it walked, and the raw view shows
// elements a screen reader never reaches (Android's uncompressed uiautomator
// dump fooled us the same way). Naming the view settles it. Measured
// 2026-09-17: both nodes were in the CONTROL view, which Narrator walks, so the
// reading was a real defect.
//
// Each line gives the control type, Name, HelpText, ItemStatus, class name,
// and the IsControlElement / IsContentElement flags. Built and run by
// p69_uia.zsh.
//
// uia_tree.c —— 從**行程外**傾印視窗的 UI Automation 樹,並指定所走的 view(raw / control / content),
// 讓每一份讀數說得出自己來自哪一棵樹。
//
// 它存在,是因為 view 曾經沒被指明,而一個正確的讀數因此被懷疑。先前一支外部 UIA 客戶端在
// P69-WinUI 底下列出了 `X` 與 `decorative`,卻沒說它走的是哪個 view;而 raw view 會列出螢幕閱讀器
// 走不到的元素(Android 未壓縮的 uiautomator dump 就這樣騙過我們一次)。指明 view 就能定案。
// 2026-09-17 實測:兩個節點都在 Narrator 所走的 **control** view 裡,所以那是真的缺陷。
//
// 每一行列出 control type、Name、HelpText、ItemStatus、class name,以及 IsControlElement /
// IsContentElement。由 p69_uia.zsh 建置並執行。
#define COBJMACROS
#include <windows.h>
#include <ole2.h>
#include <UIAutomationClient.h>
#include <stdio.h>
#include <wchar.h>

typedef struct {
    const wchar_t *needle;
    HWND found;
} FindState;

static BOOL CALLBACK find_window(HWND hwnd, LPARAM lparam) {
    FindState *state = (FindState *)lparam;
    wchar_t title[512];
    if (!IsWindowVisible(hwnd)) return TRUE;
    GetWindowTextW(hwnd, title, 512);
    if (wcsstr(title, state->needle) != NULL) {
        state->found = hwnd;
        return FALSE;
    }
    return TRUE;
}

static const wchar_t *type_name(CONTROLTYPEID id) {
    switch (id) {
    case UIA_ButtonControlTypeId: return L"button";
    case UIA_TextControlTypeId: return L"text";
    case UIA_PaneControlTypeId: return L"pane";
    case UIA_WindowControlTypeId: return L"window";
    case UIA_GroupControlTypeId: return L"group";
    case UIA_CustomControlTypeId: return L"custom";
    case UIA_SliderControlTypeId: return L"slider";
    case UIA_EditControlTypeId: return L"edit";
    case UIA_TitleBarControlTypeId: return L"titlebar";
    case UIA_ImageControlTypeId: return L"image";
    case UIA_ScrollBarControlTypeId: return L"scrollbar";
    case UIA_MenuBarControlTypeId: return L"menubar";
    default: return L"other";
    }
}

static IUIAutomationTreeWalker *walker;
static int nodes;

static void print_bstr_prop(IUIAutomationElement *e, PROPERTYID id, const wchar_t *label) {
    VARIANT v;
    VariantInit(&v);
    if (SUCCEEDED(IUIAutomationElement_GetCurrentPropertyValue(e, id, &v)) &&
        v.vt == VT_BSTR && v.bstrVal != NULL && SysStringLen(v.bstrVal) > 0) {
        wprintf(L" %ls='%ls'", label, v.bstrVal);
    }
    VariantClear(&v);
}

static void dump(IUIAutomationElement *e, int depth) {
    if (depth > 60 || nodes > 5000) return;
    nodes++;
    CONTROLTYPEID type = 0;
    BSTR name = NULL;
    BOOL isControl = FALSE, isContent = FALSE;
    IUIAutomationElement_get_CurrentControlType(e, &type);
    IUIAutomationElement_get_CurrentName(e, &name);
    IUIAutomationElement_get_CurrentIsControlElement(e, &isControl);
    IUIAutomationElement_get_CurrentIsContentElement(e, &isContent);
    wprintf(L"%*ls%ls name='%ls'", depth * 2, L"", type_name(type), name ? name : L"");
    print_bstr_prop(e, UIA_HelpTextPropertyId, L"help");
    print_bstr_prop(e, UIA_ItemStatusPropertyId, L"status");
    // FullDescription and the Value pattern as well as HelpText/ItemStatus,
    // because two toolkits put the same idea in different places: WinUI writes
    // AutomationProperties.HelpText and ItemStatus, while GTK through AccessKit
    // sends `description` and `value`, which its Windows adapter surfaces as
    // FullDescription and ValuePattern. A probe that reads only one pair grades
    // the other backend as missing what it actually has -- the same shape as
    // reading the raw UIA view and calling a control-view node a defect.
    // 同時讀 FullDescription 與 Value pattern:同一個概念在兩個工具組放在不同位置——WinUI 寫的是
    // AutomationProperties.HelpText 與 ItemStatus,而 GTK 經 AccessKit 送的是 `description` 與 `value`,
    // 由它的 Windows adapter 呈現為 FullDescription 與 ValuePattern。只讀其中一組的探針,會把另一個
    // backend「其實有的東西」判成缺失。
    print_bstr_prop(e, UIA_FullDescriptionPropertyId, L"fulldesc");
    print_bstr_prop(e, UIA_ValueValuePropertyId, L"value");
    print_bstr_prop(e, UIA_ClassNamePropertyId, L"class");
    wprintf(L" control=%d content=%d\n", isControl ? 1 : 0, isContent ? 1 : 0);
    SysFreeString(name);

    IUIAutomationElement *child = NULL;
    IUIAutomationTreeWalker_GetFirstChildElement(walker, e, &child);
    while (child != NULL) {
        dump(child, depth + 1);
        IUIAutomationElement *next = NULL;
        IUIAutomationTreeWalker_GetNextSiblingElement(walker, child, &next);
        IUIAutomationElement_Release(child);
        child = next;
    }
}

int wmain(int argc, wchar_t **argv) {
    if (argc < 3) {
        fwprintf(stderr, L"usage: uia_tree.exe <title substring> raw|control|content\n");
        return 2;
    }
    FindState state = {argv[1], NULL};
    EnumWindows(find_window, (LPARAM)&state);
    if (state.found == NULL) {
        fwprintf(stderr, L"uia_tree: no visible window title contains \"%ls\"\n", argv[1]);
        return 3;
    }
    CoInitializeEx(NULL, COINIT_MULTITHREADED);
    IUIAutomation *automation = NULL;
    HRESULT hr = CoCreateInstance(&CLSID_CUIAutomation, NULL, CLSCTX_INPROC_SERVER,
        &IID_IUIAutomation, (void **)&automation);
    if (FAILED(hr)) {
        fwprintf(stderr, L"uia_tree: CoCreateInstance failed 0x%08lx\n", hr);
        return 4;
    }
    if (wcscmp(argv[2], L"raw") == 0) {
        IUIAutomation_get_RawViewWalker(automation, &walker);
    } else if (wcscmp(argv[2], L"control") == 0) {
        IUIAutomation_get_ControlViewWalker(automation, &walker);
    } else if (wcscmp(argv[2], L"content") == 0) {
        IUIAutomation_get_ContentViewWalker(automation, &walker);
    } else {
        fwprintf(stderr, L"uia_tree: view must be raw, control or content\n");
        return 2;
    }
    IUIAutomationElement *root = NULL;
    hr = IUIAutomation_ElementFromHandle(automation, state.found, &root);
    if (FAILED(hr) || root == NULL) {
        fwprintf(stderr, L"uia_tree: ElementFromHandle failed 0x%08lx\n", hr);
        return 5;
    }
    wprintf(L"view=%ls\n", argv[2]);
    dump(root, 0);
    wprintf(L"nodes=%d\n", nodes);
    return 0;
}
