# Apple PDFKit report package

The owner reports submitting the PDFKit leak as **FB24783799**. The issue remains open pending
an Apple resolution or a verified mitigation; filing does not imply Apple has confirmed the diagnosis.
See [report text](report.md), [measurements and identities](summary.json),
[reproduction script](reproduce.sh), and [submission record](submission.json).
The public source PDF stays in the ignored corpus cache and local submission ZIP.
The debug entitlement applies only to this diagnostic executable, never the shipped library.
The submitted ZIP is retained unchanged; its preparation-time record predates the Feedback ID.
