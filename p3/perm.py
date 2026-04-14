# Helper script to compute the various cases of caching that's needed
# Author: Tim
rw = ["read", "write"]
v = ["valid", "invalid"]
d = ["dirty", "clean"]
m = ["match", "miss"]

res = set()
for r in rw:
    for va in v:
        for da in d:
            for ma in m:
                res.add((r, va, da, ma))

for t in res:
    print(t)
