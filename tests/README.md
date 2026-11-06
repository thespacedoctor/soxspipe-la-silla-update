# Test the update script

This page tells developers how to run the tests for `update-pipeline.sh`. For the update steps themselves, see the [README](../README.md).

The tests need Docker and `shellcheck`. They run in a throwaway container with stand-ins for monit, wget, conda, Ruby, and `soxspipe`, and they never touch a real install. Run this from the root of the repository:

```bash
tests/run-tests.sh
```
