import assert from "node:assert/strict";
import {
  dashboard,
  nextStages,
  scoreResult,
  escapeHTML,
  defaultCriteria,
} from "../assets/js/recruitment-model.mjs";
assert.deepEqual(nextStages("accepted"), ["hired", "no_show"]);
assert.deepEqual(nextStages("screening"), ["interview"]);
assert.equal(
  scoreResult(defaultCriteria, {
    experience: 4,
    technical: 5,
    communication: 3,
    readiness: 4,
  }),
  84,
);
assert.equal(scoreResult(defaultCriteria, { experience: 4 }), null);
assert.equal(scoreResult([{ key: "x", weight: 90 }], { x: 4 }), null);
assert.equal(escapeHTML("<script>"), "&lt;script&gt;");
assert.deepEqual(
  dashboard(
    [{ status: "open" }, { status: "hr_review" }],
    [{ stage: "hired" }, { stage: "interview" }],
  ),
  { open: 1, pending: 1, interviews: 1, hired: 1 },
);
console.log("Recruitment model: passed");
