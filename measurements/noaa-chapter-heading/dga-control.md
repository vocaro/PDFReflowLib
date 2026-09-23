# Repeated cover labels are not sparse display type

The integration of `2dea39a` with the detached-label extraction in `d22b485` exposed a
cross-document regression: DGA's six 18-point food-label lines total fewer than 200 characters,
so they establish no prose body, but they are not a sparse title. Lowering their threshold to
the document body made them headings and prevented their lines from joining into labels.

The accompanying refinement applies the sparse heading estimate only when at most two
reflowable lines use the page's dominant size. DGA therefore keeps its 18-point page body and
22.5-point heading threshold. The seven NOAA fixtures retain their heading outcomes, including
the four two-line titles. This is a restriction on evidence, not a document-name exception.

The DGA source fixture is the exact `d22b485` capture from the checksum-pinned source
`c34f1bec5c9416265670b7fcb24556bb8616ba95e8de2f2890460b6bbca1a472`. The new regression checks
both the threshold and classification of every source line; the food labels remain prose
candidates and only the two 56-point title lines are title-sized. Joining those prose labels
belongs to `d22b485` and is verified during integration, not claimed by this component test.

Validation: 100 focused heading/body/cover Swift tests, including the seven NOAA opener cases
and the DGA control. Command:

```sh
swift test --filter 'sparse|repeatedCoverLabels|establishedLargePrintProseKeepsItsOwnHeadingThreshold|typographyReadsThePageOnce|Heading|heading|Title|title|Body|body|Cover|cover|Fed|fed'
```
