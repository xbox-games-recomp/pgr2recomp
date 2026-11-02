"""Post-generation patches for pgr2recomp. Run after tools.recomp, before the build.

Each patch is (file-glob, anchor text, replacement). The anchor must be found in exactly
one place; a missing anchor is reported (the generated code changed under us).
"""
import glob,os,sys,re
GEN=os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),'src','recomp','gen','').replace('\\','/')
PATCHES=[
 # (anchor, replacement[, count]) tuples go here; see rsc2recomp/mm3recomp patch_gen.py for examples.
 # DirectSound list checks (NOTES 17): recomp_manual.c wraps these.
 ('void sub_001F0208(void)\n{', 'void sub_001F0208_gen(void)\n{'),
 ('void sub_001F0883(void)\n{', 'void sub_001F0883_gen(void)\n{'),
 ('void sub_001F028F(void)\n{', 'void sub_001F028F_gen(void)\n{'),
 ('void sub_001F0311(void)\n{', 'void sub_001F0311_gen(void)\n{'),
 # RECOMP_TEST_SUSPEND_RACE_MS (test only, NOTES 17)
 ('void sub_0018F419(void)\n{', 'void sub_0018F419_gen(void)\n{'),
]
files=sorted(glob.glob(GEN+'recomp_*.c'))
ok=True
for patch in PATCHES:
    # (anchor, replacement[, n]): the anchor must occur exactly n times (default 1) over all
    # files; n > 1 is for identical sites, every one of which is replaced.
    anchor,repl=patch[0],patch[1]
    want=patch[2] if len(patch)>2 else 1
    hits=[]; done=0
    for f in files:
        t=open(f,encoding='utf-8',errors='surrogateescape',newline='').read()
        a=anchor.replace('\n','\r\n') if '\r\n' in t[:2000] else anchor
        r=repl.replace('\n','\r\n') if '\r\n' in t[:2000] else repl
        done+=t.count(r)
        if a in t: hits.append((f,t,a,r,t.count(a)))
    if done==want:
        # Already applied (a second run over the same generated files); some replacements still
        # contain their anchor, so this has to be checked first.
        print('already patched:',anchor.splitlines()[0]); continue
    n=sum(h[4] for h in hits)
    if n!=want:
        print('PATCH ANCHOR FOUND',n,'TIMES (WANT',want,'):',anchor.splitlines()[0]); ok=False; continue
    for f,t,a,r,_ in hits:
        open(f,'w',encoding='utf-8',errors='surrogateescape',newline='').write(t.replace(a,r))
        print('patched',f.split('/')[-1])
sys.exit(0 if ok else 1)
