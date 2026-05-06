# Memory Index

- Always run the full test suite before marking any step complete
- Follow Arrange-Act-Assert strictly — no test should combine setup and assertion
- If a test requires more than 3 lines of setup, extract a helper function
- Never skip writing a test because "the change is too simple" — the test documents the contract
- When blocked by a plan ambiguity, surface it to the user instead of guessing
- Coverage threshold default: 80% — fail the step if new code falls below this
