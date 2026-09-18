# Contributing

## Reporting a problem

Open a [bug report](https://github.com/greyshepherd/hazmat/issues/new?template=bug_report.yml)
or a [feature request](https://github.com/greyshepherd/hazmat/issues/new?template=feature_request.yml)
— the template asks for what a report needs. For bugs, the status line, the
banner, and the Revert pane each say what was last written, and the Resolved
pane shows the block as text; what they show is usually the fastest route to
a cause.

## Sending a change

Pull requests are welcome. Keep them small — one behaviour per request reads
better in review.

1. Read [BUILDING.md](BUILDING.md) and make sure `swift test` passes.
2. New behaviour wants a test beside it; the composition and splice tests show
   the house style.
3. Scripts and assets are covered by the packaging tests, so run the suite
   after touching those too.
4. Match the surrounding code: comments say why, not what.

## Releases

Releases are cut by the maintainers with a signed pipeline; the process is in
[RELEASE.md](RELEASE.md). If you are sending a change that should ship in the
next release, say so in the pull request description.
