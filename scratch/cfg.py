import os,sys
v=sys.argv[1]; d=sys.argv[2]
cl={"core_swizzles":["glam_core","glam_swizzles"] if v!="b" else None,
    "core_int":["glam_core","glam_int"] if v!="a" else None}
if v=="c3": cl["core_int_swizzles"]=["glam_int","glam_int_swizzles"]
t="[gates]\nmax_lines = 40000\nmax_seconds = 5\nmax_gb = 1\nclosure_seconds = 15\nclosure_gb = 3\n\n[closures]\n"
for k,m in cl.items():
    if m: t+=f'{k} = [{", ".join(chr(34)+x+chr(34) for x in m)}]\n'
open(d+"/consumer_cost.toml","w").write(t)
