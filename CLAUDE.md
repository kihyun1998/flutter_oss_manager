## Agent skills

- Before reading, filing, labelling or closing an issue, read `docs/agents/issue-tracker.md`.
- Before applying a triage label, read `docs/agents/triage-labels.md`.
- Before naming a domain concept or working in an area a decision record covers, read `docs/agents/domain.md`.

## Comments

A comment says what the code is. Why it is this way, what it deliberately leaves out, the trap and the measured value go to the territory note under `docs/map/`. Where none seems to hold it, search the folder and the code symbol first; only then start a new note, named for what the system does there, not for the file. History goes to the commit message. Comments written before this rule still carry the rest: never delete one whose content the map does not yet hold — move it there first.

## Territory map

[`docs/map/README.md`](docs/map/README.md). Before designing a change, open the territories it touches and follow their blast radius and invariants. After it lands, update the notes it made false. When a fix reveals a fact, ask whether it holds at every site that shares the same assumption; if yes, the fix lands with an invariant note.
