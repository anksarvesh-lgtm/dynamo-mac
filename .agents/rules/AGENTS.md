# Agent rules

Always pass project_path (the full path of this workspace) to agent-guard tools.

Start
1. Call task_status. If a task is active, continue it. Do not start over.
2. If none is active: call repo_brief, then task_start with a goal and 3 to 12 steps.
3. Use the code-map tools to find code before opening files. Open a file only to edit it or when the map cannot answer.

Work
4. After every step call task_checkpoint with proof in the note (for example the test result).
5. After every error call task_checkpoint with status failed and the error text. Fix the cause and retry the same step. Do not start another step while this one has tries left.
6. If a step is reported blocked, write why and go on with the next allowed step.
7. Do not stop while unblocked steps remain. Ask the user only about choices that change what the product does, never about things you can find out by reading code or running a test.
8. Commit to git after each finished step. Ensure zero git errors occur: always verify git status and path existence before staging/committing, avoid committing clean working trees, and use -f when updating moving tags.

Finish
9. When task_status says the task is done, reply with 3 lines: what changed, what you tested, what is blocked.
Never run denied commands. Never read or print secret files.

