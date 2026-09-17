# Episode / Broadcast Reconciliation

`episodes.json` is the canonical list of 1,399 CBS RMT episodes.

`cbsrmt_episode_dataset.json` is broadcast history and must encode each row as exactly one of:

1. **original**: `episode_id` set, `repeat_of_episode_id` null.
2. **repeat**: `episode_id` null, `repeat_of_episode_id` set to the canonical episode.
3. **no broadcast**: both fields null.

The staging loader corrects two same-title false-repeat classifications discovered during reconciliation:

- episode 1313, `You Tell Me Your Dream`, 1982-04-09.
- episode 1382, `Flash Point [The]`, 1982-10-15.

It also fills the three missing calendar dates 1982-01-01 through 1982-01-03 as explicit no-broadcast rows and reconstructs `sequence_number` as `broadcast_sequence`: the ordinal of actual broadcasts (originals + repeats), excluding no-broadcast dates.

Production normalization stores `broadcast_type` plus a single canonical `episode_number`; it does not preserve the mutually-exclusive JSON identifiers as separate production columns.
