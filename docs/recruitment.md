# Recruitment — initial operational release

## Workflow

Requisition → HR review → budget review → final approval → open vacancy → screening → interview → assessment → recommendation → offer finance review → offer approval → recorded dispatch → recorded acceptance → document verification → actual joining.

Each requisition explicitly names its HR reviewer, budget reviewer, final approver and interview participants. This is configuration by the operator; the release does not invent a company-wide approval matrix. The existing account page controls access to the `recruitment` unit and its three additional permissions: manage, finance and approve. Managers with unit access may request vacancies and refer candidates. Designated participants see the vacancies they work on. Salaries/offers are redacted for ordinary requesters and interviewers.

Both advertised recruiting and department referrals use the same approvals. Referrals do not require an advertisement or candidate-count threshold. Previous interviews can be documented with the real date, interviewer, criterion scores, evidence and recommendation. The user must advance the application after completing the assessment; no score automatically hires or rejects anyone.

## Existing references

Published job descriptions are copied into requisition snapshots. Compensation is imported into a private table from approved compensation Site source `ec77eba804232fcaca16c38f63e9894a98623e65`. Actual compensation amounts are deliberately excluded from this public repository. The import contains 61 reference rows, including separate executive and general manager entries. An exact salary-title match is linked automatically; HR records the match for other titles before approval. Nonidentical titles are never guessed. Both references remain frozen on the approved request and its offer versions. Updating the standalone compensation reference does not silently change existing requisitions.

All salary checks use total monthly basic + housing + transport, according to the approved source. An unavailable category range blocks an offer. Out-of-range offers require a recorded exception reason and still pass the named financial and final approvers. Current employee compensation is never altered by this release; only a newly created employee receives the accepted offer's amounts. Linking an existing employee requires explicit confirmation of that employee's ID and preserves their record.

## Public intake and files

`recruitment/careers.html` lists only explicitly published open advertised vacancies. Draft, closed and referral vacancies are excluded. Only the public job projection is returned; neither salaries nor candidate records are exposed. An applicant submits their data with consent and may attach one PDF up to 5 MiB. The private storage bucket allows anonymous INSERT only using an unpredictable, one-hour application upload ticket. Anonymous read, replacement and deletion are not granted. Duplicate submissions receive a generic acknowledgement and an unrelated receipt rather than exposing an existing application or file token. Internal readers need access to the related vacancy. Staff can add a PDF to a referred application through its file page. Signed reading links last two minutes.

Public intake is capped at 300 new applications per vacancy per day. This is a basic quota, not identity verification or an advanced anti-abuse service.

## Hiring integrity

The backend locks the application and requisition when accepting an offer or recording joining. Accepted and hired applications reserve the headcount; joining closes the requisition only after the requested number has actually started. A no-show frees the reservation. Stale requisition/application revisions are rejected. Terminal records cannot be advanced. Offers retain versions; an already sent offer must receive a documented response before another is prepared. An offer cannot be marked accepted after its validity date.

The release creates no Auth accounts, sends no external email and makes no real hiring decisions automatically. Dispatch and candidate acceptance are recorded by HR with their evidence reference. In-app notifications and pending-action queues support follow-up.

## Validation

- All 124 top-level JavaScript regression suites.
- `npm run test:recruitment:db`: isolated real PostgreSQL execution via PGlite, covering unit/account boundaries, direct grants, referrals, previous interview evaluations, salary exceptions, offer approvals, duplicate/terminal joins, headcount, public projection, upload tickets and anonymous storage isolation.
- Browser QA on synthetic data using the existing theme: job/application detail, documented previous interview, calculated score, stage transitions and offer creation; responsive layout checked in a 390px iframe.

## Scope still requiring business input or subsequent integration

- The 10–5–5 policy is not enforced until its intended operational meaning is confirmed.
- Company-wide default approval owners and target durations require the approved matrix; this release uses explicit owners per requisition and a target joining date.
- External email delivery, e-signatures, calendar invitations and automatic synchronization from the standalone salary Site are not enabled.
- Document completion is an HR verification confirmation and evidence note, not a configurable document-management workflow.
- Reports currently cover pipeline counts and overdue target joining dates; source conversion, historical time-to-fill analytics and a dedicated comparison report are subsequent enhancements.
