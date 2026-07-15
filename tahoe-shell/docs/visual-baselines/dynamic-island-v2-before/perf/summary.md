# 10-minute idle performance baseline

Sampling command:

```bash
# every 2s for 300 samples (600s)
ps -o pcpu=,rss=,etime= -p <quickshell-pid>
```

Raw CSV: `quickshell-idle-10m.csv`
Meta: `sample-meta.txt`

| metric | value |
| --- | ---: |
| samples | 300 |
| CPU median | 2.2 % |
| CPU p95 | 7.810000000000002 % |
| CPU mean | 3.1003 % |
| CPU min | 1.8 % |
| CPU max | 11.8 % |
| RSS median | 648812.0 KiB (633.61 MiB) |
| RSS peak | 766648 KiB (748.68 MiB) |
| RSS min | 633296 KiB |
