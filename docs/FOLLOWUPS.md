---
type: roadmap
links:
  - rel: part-of
    to: CLAUDE.md
---

# Follow-ups

Deliberate deferrals. Remove an entry when it ships.

## Warn when the printer will drop a setting

A printer can accept a job and ignore part of it: the Brother HL-L3280CDW prints one-sided when
the job's media type is one it can't duplex (labels, envelopes), and the bar still shows Double
and then "Done".

- **Next action:** before `lp`, send IPP `Validate-Job` with the job's attributes to the
  printer itself (its device URI, not the CUPS queue, which validates against the PPD only). On
  `successful-ok-ignored-or-substituted-attributes`, block Print with the ignored attributes as
  the reason, e.g. "This printer can't print labels double-sided".
- **Blocker:** none. Needs the device URI from `lpstat -v` (a `dnssd://` URI resolves to the
  printer's `ipp(s)://` address) and an IPP client in RoneoCore, or `ipptool` behind
  `CommandRunner`.
