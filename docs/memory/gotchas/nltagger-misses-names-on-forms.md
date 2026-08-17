# Gotcha: NLTagger does not find names on forms

**Status:** worked around by `LabelledFieldDetector` (2026-08-17, fixer pass, Phase 2).
One residual defect is open and listed at the bottom.

## What happened

The verifier reported that the exported sample "renders `Employee  Ananya Mehra` with NO bar", and
attributed it to sub-line geometry drift. That attribution was wrong, and the truth is worse: the
employee's name **was never detected at all**. Printing the real pipeline output on the bundled
sample gave

```
place:Northwind  personName:Whitefield  organisation:Bengaluru  personName:August
pan:AZZPQ4821K  aadhaar:9999 8888 7779  phone:+91 90000 12345
dateOfBirth:14/03/1994  email:ananya.mehra@example.com  ifsc:ZZZZ0123456
```

Ten detections — the count the UI showed — and not one of them the name. The bar the verifier saw
over "August" was not a drifted name bar; it was a genuine `NLTagger` false positive on the page
title, sitting next to a genuine false *negative* on the name.

`NLTagger(.nameType)` is trained on prose. Given the bare string `Employee Ananya Mehra` it returns
**nothing**. It has no sentence context, and it has not memorised the name. A model that has never
seen a name has no way to know it is one — which is a property, not a bug, and it means NER alone
can never be the name-detection strategy for a privacy tool used outside the languages the model
was trained on.

Compounding it: OCR reads the sample's two-column employee block as a *stack* —
`Employee` / `Ananya Mehra` / `PAN` / `AZZPQ4821K` — so the label and its value are never in the
same string, and no single-line detector can see the pair.

## The fix

`Core/Detection/LabelledFieldDetector.swift`. A printed label is evidence: whatever sits in the
value position of `Employee`, `Account Holder`, `Beneficiary Name` … is a person's name whether or
not a model recognises it, in every language. Two shapes are handled — inline
(`Employee: Ananya Mehra`) and stacked across consecutive OCR lines, via
`HeuristicClassifier.labelledNamesAcrossLines`. `PatternDetector` already used this reasoning for
`Date of Birth:`.

The risk of a label rule is the opposite failure — bars over job titles and reference codes, which
teaches users to switch bars off. So the label set is deliberately narrow (`Designation` and
`Employee ID` are excluded), and `looksLikeAPersonName` rejects anything containing a digit. Half of
`Tests/DetectionTests/LabelledFieldDetectorTests.swift` is about that.

The sample now yields 11 detections including `personName:Ananya Mehra`, and the exported PNG pulled
out of the simulator container covers it.

## Still open — for a future detection pass, not a fixer pass

`NLTagger` tags **"August"** in `Salary Slip — August 2026` as a `personName`, so the demo burns a
bar over the page title's month. It is over-redaction, not a leak: the user can switch it off, and
the detection sheet lists it. It was left alone deliberately — suppressing month names is a change
to detection *quality* with its own false-negative risk (people are named August), it was not one of
the verifier's findings, and a one-pass fixer widening detection rules unprompted is how scope
creep starts. Whoever owns `detect-engine` next should decide whether a document-context rule
("a month name adjacent to a four-digit year is a date, not a person") is worth it.
