Identity and success: all candidate outputs byte-identical to the baseline and all conversions succeeded

**Sampled peak physical footprint, MiB**

| Case | baseline | resident | spill | reextract |
| --- | ---: | ---: | ---: | ---: |
| cdc-zombie-pandemic-2011 | 211.4 | 213.5 | 206.3 | 208.3 |
| cia-blue-book-14-1955 | 142.8 | 142.4 | 130.3 | 130.5 |
| dga-2025-2030 | 67.4 | 67.8 | 65.2 | 68.3 |
| faa-phak-8083-25c | 514.4 | 517.1 | 515.8 | 516.8 |
| fed-explained-2021 | 228.3 | 232.5 | 252.4 | 230.4 |
| gpo-911-2004 | 162.2 | 161.4 | 157.1 | 155.5 |
| gpo-our-flag-2003 | 154.4 | 158.6 | 162.9 | 156.0 |
| gpo-warren-1964 | 336.4 | 322.9 | 305.1 | 304.7 |
| noaa-nca5-2023 | 384.8 | 328.0 | 293.3 | 299.9 |
| wallace-algebra-2010 | 66.4 | 62.8 | 53.8 | 62.0 |

**Peak RSS, MiB**

| Case | baseline | resident | spill | reextract |
| --- | ---: | ---: | ---: | ---: |
| cdc-zombie-pandemic-2011 | 364.8 | 366.5 | 366.1 | 366.5 |
| cia-blue-book-14-1955 | 158.0 | 157.7 | 145.4 | 148.1 |
| dga-2025-2030 | 100.9 | 100.8 | 100.6 | 102.2 |
| faa-phak-8083-25c | 810.2 | 809.5 | 793.1 | 812.3 |
| fed-explained-2021 | 283.0 | 281.0 | 279.7 | 282.1 |
| gpo-911-2004 | 125.8 | 102.6 | 93.4 | 102.5 |
| gpo-our-flag-2003 | 87.2 | 88.1 | 93.0 | 85.9 |
| gpo-warren-1964 | 937.6 | 919.8 | 902.0 | 901.7 |
| noaa-nca5-2023 | 981.9 | 935.9 | 910.1 | 911.3 |
| wallace-algebra-2010 | 84.7 | 82.9 | 73.0 | 80.5 |

**Conversion seconds**

| Case | baseline | resident | spill | reextract |
| --- | ---: | ---: | ---: | ---: |
| cdc-zombie-pandemic-2011 | 6.97 | 6.84 | 7.06 | 6.83 |
| cia-blue-book-14-1955 | 29.10 | 28.67 | 29.59 | 30.06 |
| dga-2025-2030 | 0.74 | 0.73 | 0.73 | 0.73 |
| faa-phak-8083-25c | 36.60 | 36.58 | 38.19 | 51.50 |
| fed-explained-2021 | 6.57 | 6.57 | 6.57 | 7.39 |
| gpo-911-2004 | 9.98 | 10.09 | 10.50 | 15.90 |
| gpo-our-flag-2003 | 1.24 | 1.25 | 1.25 | 1.66 |
| gpo-warren-1964 | 11.94 | 12.05 | 12.61 | 13.41 |
| noaa-nca5-2023 | 126.40 | 125.38 | 132.19 | 166.33 |
| wallace-algebra-2010 | 9.48 | 9.27 | 9.98 | 13.00 |

**Peak run-directory bytes, MiB**

| Case | baseline | resident | spill | reextract |
| --- | ---: | ---: | ---: | ---: |
| cdc-zombie-pandemic-2011 | 234.3 | 235.0 | 212.9 | 233.8 |
| cia-blue-book-14-1955 | 358.8 | 391.9 | 408.1 | 374.5 |
| dga-2025-2030 | 7.6 | 7.6 | 7.6 | 7.6 |
| faa-phak-8083-25c | 517.5 | 517.1 | 481.2 | 535.9 |
| fed-explained-2021 | 109.1 | 113.6 | 113.4 | 126.4 |
| gpo-911-2004 | 73.0 | 79.4 | 109.9 | 86.5 |
| gpo-our-flag-2003 | 13.1 | 13.1 | 13.1 | 13.3 |
| gpo-warren-1964 | 13.7 | 26.3 | 15.8 | 13.7 |
| noaa-nca5-2023 | 2,878.7 | 2,879.7 | 2,874.0 | 2,884.8 |
| wallace-algebra-2010 | 82.9 | 92.0 | 55.0 | 58.9 |

### cdc-zombie-pandemic-2011

| Run | Seconds | CPU s | Peak RSS MiB | Sampled footprint MiB | Peak run directory MiB | Identical | EPUBCheck |
| --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| baseline | 6.97 | 6.72 | 364.8 | 211.4 | 234.3 | reference | pass |
| resident | 6.84 | 6.69 | 366.5 | 213.5 | 235.0 | yes |  |
| spill | 7.06 | 6.75 | 366.1 | 206.3 | 212.9 | yes |  |
| reextract | 6.83 | 6.77 | 366.5 | 208.3 | 233.8 | yes |  |

### cia-blue-book-14-1955

| Run | Seconds | CPU s | Peak RSS MiB | Sampled footprint MiB | Peak run directory MiB | Identical | EPUBCheck |
| --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| baseline | 29.10 | 28.95 | 158.0 | 142.8 | 358.8 | reference | pass |
| resident | 28.67 | 28.51 | 157.7 | 142.4 | 391.9 | yes |  |
| spill | 29.59 | 29.38 | 145.4 | 130.3 | 408.1 | yes |  |
| reextract | 30.06 | 29.87 | 148.1 | 130.5 | 374.5 | yes |  |

### dga-2025-2030

| Run | Seconds | CPU s | Peak RSS MiB | Sampled footprint MiB | Peak run directory MiB | Identical | EPUBCheck |
| --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| baseline | 0.74 | 0.61 | 100.9 | 67.4 | 7.6 | reference | pass |
| resident | 0.73 | 0.62 | 100.8 | 67.8 | 7.6 | yes |  |
| spill | 0.73 | 0.62 | 100.6 | 65.2 | 7.6 | yes |  |
| reextract | 0.73 | 0.67 | 102.2 | 68.3 | 7.6 | yes |  |

### faa-phak-8083-25c

| Run | Seconds | CPU s | Peak RSS MiB | Sampled footprint MiB | Peak run directory MiB | Identical | EPUBCheck |
| --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| baseline | 36.60 | 37.21 | 810.2 | 514.4 | 517.5 | reference | pass |
| resident | 36.58 | 37.32 | 809.5 | 517.1 | 517.1 | yes |  |
| spill | 38.19 | 38.78 | 793.1 | 515.8 | 481.2 | yes |  |
| reextract | 51.50 | 52.14 | 812.3 | 516.8 | 535.9 | yes |  |

### fed-explained-2021

| Run | Seconds | CPU s | Peak RSS MiB | Sampled footprint MiB | Peak run directory MiB | Identical | EPUBCheck |
| --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| baseline | 6.57 | 6.69 | 283.0 | 228.3 | 109.1 | reference | pass |
| resident | 6.57 | 6.72 | 281.0 | 232.5 | 113.6 | yes |  |
| spill | 6.57 | 6.77 | 279.7 | 252.4 | 113.4 | yes |  |
| reextract | 7.39 | 7.61 | 282.1 | 230.4 | 126.4 | yes |  |

### gpo-911-2004

| Run | Seconds | CPU s | Peak RSS MiB | Sampled footprint MiB | Peak run directory MiB | Identical | EPUBCheck |
| --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| baseline | 9.98 | 10.26 | 125.8 | 162.2 | 73.0 | reference | pass |
| resident | 10.09 | 10.23 | 102.6 | 161.4 | 79.4 | yes |  |
| spill | 10.50 | 10.71 | 93.4 | 157.1 | 109.9 | yes |  |
| reextract | 15.90 | 16.15 | 102.5 | 155.5 | 86.5 | yes |  |

### gpo-our-flag-2003

| Run | Seconds | CPU s | Peak RSS MiB | Sampled footprint MiB | Peak run directory MiB | Identical | EPUBCheck |
| --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| baseline | 1.24 | 1.06 | 87.2 | 154.4 | 13.1 | reference | pass |
| resident | 1.25 | 1.07 | 88.1 | 158.6 | 13.1 | yes |  |
| spill | 1.25 | 1.08 | 93.0 | 162.9 | 13.1 | yes |  |
| reextract | 1.66 | 1.35 | 85.9 | 156.0 | 13.3 | yes |  |

### gpo-warren-1964

| Run | Seconds | CPU s | Peak RSS MiB | Sampled footprint MiB | Peak run directory MiB | Identical | EPUBCheck |
| --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| baseline | 11.94 | 11.59 | 937.6 | 336.4 | 13.7 | reference | pass |
| resident | 12.05 | 11.81 | 919.8 | 322.9 | 26.3 | yes |  |
| spill | 12.61 | 12.38 | 902.0 | 305.1 | 15.8 | yes |  |
| reextract | 13.41 | 13.19 | 901.7 | 304.7 | 13.7 | yes |  |

### noaa-nca5-2023

| Run | Seconds | CPU s | Peak RSS MiB | Sampled footprint MiB | Peak run directory MiB | Identical | EPUBCheck |
| --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| baseline | 126.40 | 143.71 | 981.9 | 384.8 | 2,878.7 | reference | pass |
| resident | 125.38 | 143.28 | 935.9 | 328.0 | 2,879.7 | yes |  |
| spill | 132.19 | 148.85 | 910.1 | 293.3 | 2,874.0 | yes |  |
| reextract | 166.33 | 181.32 | 911.3 | 299.9 | 2,884.8 | yes |  |

### wallace-algebra-2010

| Run | Seconds | CPU s | Peak RSS MiB | Sampled footprint MiB | Peak run directory MiB | Identical | EPUBCheck |
| --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| baseline | 9.48 | 10.16 | 84.7 | 66.4 | 82.9 | reference | pass |
| resident | 9.27 | 10.09 | 82.9 | 62.8 | 92.0 | yes |  |
| spill | 9.98 | 10.75 | 73.0 | 53.8 | 55.0 | yes |  |
| reextract | 13.00 | 13.83 | 80.5 | 62.0 | 58.9 | yes |  |

