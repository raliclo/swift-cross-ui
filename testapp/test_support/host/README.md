# host — this PC's settings that the test runs depend on

`wslconfig` is a byte-for-byte copy of `%UserProfile%\.wslconfig`, kept here because it is outside every
repository and the WSL test runs depend on it: mirrored networking, an 8 GB
memory cap, and `autoMemoryReclaim=DropCache`. Each setting carries its reason
in the file itself.

Restore it, then restart WSL so it takes effect:

```sh
cp testapp/test_support/host/wslconfig ~/.wslconfig
wsl --shutdown    # stops every distro, multisshd included
```

Check that the copy has not drifted from the live file:

```sh
cmp ~/.wslconfig testapp/test_support/host/wslconfig && printf 'same\n'
```

Copied 2026-10-22, after the memory cap and reclaim were added. It holds no
secrets: networking mode, a memory cap, two experimental switches, and
comments -- no addresses, accounts, keys or proxy settings. Keep it that way;
anything secret belongs in the live file only.

---

# host——測試執行所依賴的本機設定

`wslconfig` 是 `%UserProfile%\.wslconfig` 逐位元組的拷貝。放在這裡，是因為它不在
任何 repository 裡，而 WSL 的測試執行依賴它:mirrored 網路、8 GB 記憶體上限，以及 `autoMemoryReclaim=DropCache`。
每項設定的理由都寫在檔案本身。

還原後重開 WSL 才會生效(`wsl --shutdown` 會停掉所有 distro,包括 multisshd);用上面的 `cmp` 確認拷貝沒有和
實際的檔案分歧。2026-10-22 加入記憶體上限與回收設定後拷貝。內容不含機密：只有網路模式、記憶體上限、兩個 experimental 開關與註解，
沒有位址、帳號、金鑰或 proxy 設定。請維持如此；任何機密只放在實際的檔案裡。
