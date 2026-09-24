# Recovered table rows stop at a separately spaced prose paragraph

The final magazine audit found the USDA magazine's physical page 3 copyright
paragraph becoming preformatted rows after the decorative panel's staff contacts
were recovered. The existing row detector extended their shared 8.3-point type and
left margin across the paragraph gap. The source raster confirms four complete
wrapped prose rows below the last telephone number; the first baseline gap is
12.16 points versus the contact rows' approximately 10-point leading.

A row run now stops at a larger baseline gap when the following four rows prove
full-measure prose on the same outer edge, with stable size/leading, lowercase
continuations, no list or terminal numeric entries, and a complete sentence.
Indented cell continuations provide no such evidence. This leaves the staff rows
and their numeric associations intact while reconstructing the copyright as prose.
The exact source capture and a no-gap negative control pass, along with all 79
table-related Swift tests. The complete corpus
adds checks for the copyright paragraph and two staff telephone entries.

The other page-3 audit flag is an improvement: the picture caption's five false
headings become one ordinary paragraph. Every source character remains available.
Raw source/output images and diagnostic logs remain outside Git.
