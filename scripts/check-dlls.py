# XnX: verify every DLL imported by shipped binaries resolves at runtime.
# A DLL is OK if it (a) ships in the bundle, or (b) is a known Windows system
# DLL. Anything else fails the build — prevents "vulkan-1.dll missing" on a
# clean user machine.
import os
import struct
import sys

BUNDLE = sys.argv[1] if len(sys.argv) > 1 else 'bundle'

# Windows ships these (system32 / WinSxS). Include UCRT api-ms-win-* which are
# OS components on Windows 10+, and the VC runtime redistributable DLLs we
# also ship in the bundle.
SYSTEM_PREFIXES = (
    'kernel32', 'user32', 'gdi32', 'advapi32', 'shell32', 'shlwapi',
    'ole32', 'oleaut32', 'version', 'winmm', 'ws2_32', 'wldap32',
    'crypt32', 'secur32', 'imm32', 'setupapi', 'iphlpapi', 'avrt',
    'avicap32', 'dwrite', 'd2d1', 'dwmapi', 'opengl32', 'normaliz',
    'shcore', 'bcrypt', 'bcryptprimitives', 'ntdll', 'uxtheme',
    'cfgmgr32', 'combase', 'comctl32', 'd3d11', 'dbghelp', 'mfplat',
    'psapi', 'userenv', 'windowscodecs', 'msimg32', 'winspool',
    'api-ms-win-', 'ext-ms-win-', 'msvcrt', 'vcruntime', 'ucrtbase',
)

def pe_imports(path):
    with open(path, 'rb') as f:
        d = f.read()
    if d[:2] != b'MZ':
        return []
    e_lfanew = struct.unpack_from('<I', d, 0x3c)[0]
    coff = e_lfanew + 4
    opt = coff + 20
    magic = struct.unpack_from('<H', d, opt)[0]
    pe32p = magic == 0x20b
    dd_off = opt + (112 if pe32p else 96)
    imp_rva, _ = struct.unpack_from('<II', d, dd_off + 8)
    nsec = struct.unpack_from('<H', d, coff + 2)[0]
    sec_off = opt + struct.unpack_from('<H', d, coff + 16)[0]
    secs = []
    for i in range(nsec):
        s = sec_off + i * 40
        va, vs, raw, rs = struct.unpack_from('<IIII', d, s + 12)
        secs.append((va, vs, raw, rs))
    def rva2off(rva):
        for va, vs, raw, rs in secs:
            if va <= rva < va + max(vs, rs):
                return raw + (rva - va)
        return None
    out = []
    off = rva2off(imp_rva)
    if off is None:
        return out
    while off + 20 <= len(d):
        ent = d[off:off + 20]
        if ent == b'\0' * 20:
            break
        name_rva = struct.unpack_from('<I', ent, 12)[0]
        no = rva2off(name_rva)
        if no:
            end = d.find(b'\0', no)
            if end > no:
                out.append(d[no:end].decode('ascii', errors='ignore'))
        off += 20
    return out

shipped = {f.lower() for _, _, fs in os.walk(BUNDLE) for f in fs}
missing = {}
for root, _, files in os.walk(BUNDLE):
    for f in files:
        if not f.lower().endswith(('.exe', '.dll')):
            continue
        p = os.path.join(root, f)
        for dll in pe_imports(p):
            low = dll.lower()
            if low in shipped:
                continue
            if low.startswith(SYSTEM_PREFIXES):
                continue
            missing.setdefault(low, []).append(os.path.relpath(p, BUNDLE))

if missing:
    print('MISSING DLL DEPENDENCIES (not in bundle, not a system DLL):')
    for dll, consumers in sorted(missing.items()):
        print(f'  {dll} <- {", ".join(consumers[:4])}')
    sys.exit(1)
print(f'DLL CHECK PASS: all dependencies of shipped binaries resolve '
      f'({len(shipped)} files in bundle)')
