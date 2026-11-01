# Table paging CLI admission — dev109

The existing native document-table pager exposed six typed actions, while the
public Python GUI-test frontend rejected every `table_page` request before
attachment. Add those same actions to the existing frontend and author-tools
reference; retain the original attachment, Session and source guards. No C++
capability or native pager implementation changes.

`goto` transports an exact signed decimal string of at most 32 characters.
The native Go field retains responsibility for source-row range validation.
Other commands reject a row argument, and undeclared fields/components remain
invalid.

The actual frontend regression has 26 cases: baseline 10 failures, corrected
version zero. The admitted cases stop at `GUI_TEST_NOT_ATTACHED`, with no
mailbox, GUI input, source mutation or scientific operation. These checks are
frontend admission evidence, not installed GUI acceptance. Independent Table
author205 owns the attached native acceptance.

Evidence: `/srv/gxtxt/agents/tests/gui_table_page208_before/receipt.json` and
`/srv/gxtxt/agents/tests/gui_table_page208_after/receipt.json`.
