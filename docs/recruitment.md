# Recruitment — approved workflow

The module uses the existing Atwar One theme, account permissions and employee register. The uploaded offer image and requisition workbook are reference material, not approved templates. No personal details or salary amounts from either are embedded in the source.

## Requisitions and exceptions

The supervisor saves a draft, then submits to department manager → personnel specialist → financial director → CEO → designated recruiter. Submission requires a published job description, linked grade/range and current target date. Personnel approval requires explicit checks of new/replacement status, Saudization plan and profession eligibility. These are human checks; no inferred legal exemption is made by the application.

Personnel rejection requires an explicit, justified exception request from the supervisor; the development supervisor may approve it, then the request continues to finance. A finance exception goes to the CEO, whose approval is the final approval and releases the request directly to the recruiter. Rejected requests may be edited, preserving the old snapshot and decision events; resubmission restarts department approval. Recruiters may amend offers, not requisitions. A cancelled request remains closed; the creation form can copy it into a new linked request. A departed hire is handled through a new linked replacement request.

Department managers may cancel with a reason. If any candidate has accepted or joined, cancellation requires CEO approval. No automatic replacement is created for an internal transfer.

## Sourcing and selection

Search requisitions present batches of exactly 10, then 5 new candidates, then 5 new candidates. Incoming applications do not count until presented. Every rejection is recorded by the department manager with its reason. A further batch starts only after the prior batch has no selected candidate and all rejection reasons are recorded. After three exhausted batches, sourcing stops while the requisition stays open. The development supervisor can authorize another batch with an explicit count and justification addressing requirements, pay and evaluation. Existing suitable candidates can be reconsidered without resetting or consuming new candidate counts.

Department referrals bypass advertisement and batches. Previously held interviews can be documented. The direct supervisor records the first technical assessment. The department manager approves selection and records a second assessment only when they request a second interview with a reason. Recruiters schedule and coordinate, but cannot submit completed assessments on behalf of either manager. Scores never choose a candidate automatically.

Each candidate has a single file, with unique email, identity/residence number and passport number plus issuing country. Conflicting identity/email matches are blocked. A recruiter may link a candidate to another visible open requisition after documenting consent and fit; previous assessments remain available. There is no permanent blacklist. Interview participants have access to pay and documents only on their assigned requests. Recruiters with the management permission retain the recruitment-wide working view.

Internal candidates are linked to an existing employee. The current department approves release, the receiving department approves selection, and the CEO authorizes the actual transfer. The existing compensation is not changed automatically. No external offer or automatic replacement requisition is generated.

## Offers and joining

Recruiter prepares → personnel specialist reviews → CEO approves → recruiter records dispatch. Finance has no offer approval. Salary or benefit deviations require a justified development-supervisor recommendation before CEO approval. Every edited offer is a new version with an amendment reason and a fresh review cycle. CEO rejection returns it for amendment. The approved private compensation reference supplies the frozen salary range and grade benefits; current employee pay is not changed. Reference source: `ec77eba804232fcaca16c38f63e9894a98623e65`.

Offers are valid for seven calendar days from recorded sending. The recruiter may extend by seven days with a reason, preserving terms. Live sent offers and accepted/hired candidates cannot exceed approved headcount. The recruiter is reminded to reconsider suitable reserve candidates when an offer is declined or expires. Production does not send external messages or sign contracts automatically.

Required documents: identity/residence, passport, education, experience, national address and IBAN certificate; driving licence for driver/representative titles; dependants' identities when applicable. PDFs up to 5 MiB are versioned and privately stored. The recruiter reviews each document. Missing documents require recruiter approval, a reason and a completion deadline, remaining in the follow-up queue until complete.

The supervisor confirms actual attendance and joining date. The recruiter then verifies the documents or valid exception and completes employee registration. A postponed start requires recorded coordination with the supervisor. Full actual headcount closes the requisition, stops the advert and notifies the recruiter to resolve remaining applications.

## Candidate update link

A recruiter generates a private, unguessable link valid for seven days. It returns only vacancy title and link expiry, accepts candidate changes into a pending review queue, and creates insert-only one-hour PDF upload tickets. Existing candidate data and files are never readable anonymously. Updates do not alter the candidate record before recruiter approval. Staff retain previous document versions and a history of approved changes. Expired links cannot submit; a new link can be issued. No link is sent externally by the system in this release.

## Deadlines and notifications

- Each requisition stage and each offer preparation/review/approval: two business days.
- First batch: ten business days, or fifteen with a documented specialist/leadership justification and notification to the requester.
- Additional batches: five business days, starting after documented non-selection.
- Department evaluation of a batch and review/interview/decision on a referral: three business days.
- Friday, Saturday, National Day, Foundation Day and the approved additional holiday calendar are excluded. The development supervisor maintains other officially declared dates, including Eid and substitute days, through the reference screen.
- Every thirty minutes a private scheduled job checks overdue tasks, notifies the owner once and escalates once to the recruiter after another business day. No email or WhatsApp is sent.

## Permissions and setup

The existing Accounts page exposes recruiter management, personnel review, finance budget review, development exceptions and CEO approval. Each requisition names active authorized owners for the stages and its direct supervisor/department manager. No real account grants, hiring choices, notifications to external recipients or compensation changes are performed by the migration itself.

## Validation

`npm run test:recruitment:db` runs the original baseline database checks and the approved-workflow integration suite against isolated PostgreSQL. It covers per-request disclosure, explicit exceptions, 10/5/5 limits, personal interview assessments, selection ownership, offer finance denial, joining and document prerequisites, candidate changes, cancellation, request snapshots, calendar arithmetic and deduplicated reminders. Existing JavaScript and fleet regressions are run separately. Browser QA uses synthetic records and the production theme; no real employee or applicant is created for verification.
