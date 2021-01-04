# GitHub action to automatically rebase PRs

[![Build Status](https://api.cirrus-ci.com/github/cirrus-actions/rebase.svg)](https://cirrus-ci.com/github/cirrus-actions/rebase) [![](https://images.microbadger.com/badges/version/cirrusactions/rebase.svg)](https://microbadger.com/images/cirrusactions/rebase) [![](https://images.microbadger.com/badges/image/cirrusactions/rebase.svg)](https://microbadger.com/images/cirrusactions/rebase)

After installation simply comment `/rebase` or `/autosquash` or `rebase+` to trigger the action:

![rebase-action](https://user-images.githubusercontent.com/989066/51547853-14a57b00-1e35-11e9-841d-33114f0f0bd5.gif)

# Commands description
- `/rebase` - Rebase PR branch on the HEAD of the base
- `/autosquash` - Autosquash the PR without rebasing on the base branch
- `/rebase+` - Rebase PR branch on the HEAD of the base and autosquash commits

# Installation

To configure the action simply add the following lines to your `.github/workflows/rebase.yml` workflow file:

```yml
on: 
  issue_comment:
    types: [created]
name: Automatic Rebase/Autosquash
jobs:
  rebase:
    name: Rebase
    if: github.event.issue.pull_request != '' && (contains(github.event.comment.body, '/rebase') || contains(github.event.comment.body, '/autosquash') || contains(github.event.comment.body, '/rebase+'))
    runs-on: ubuntu-18.04
    steps:
    - name: Checkout the latest code
      uses: actions/checkout@v2
      with:
        fetch-depth: 0
    - name: Rebase/Autosquash
      uses: wandera/rebase@master
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## Restricting who can call the action

It's possible to use `author_association` field of a comment to restrict who can call the action and skip the rebase for others. Simply add the following expression to the `if` statement in your workflow file: `github.event.comment.author_association == 'MEMBER'`. See [documentation](https://developer.github.com/v4/enum/commentauthorassociation/) for a list of all available values of `author_association`.
