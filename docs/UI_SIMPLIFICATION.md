# تبسيط الشيكات | Simple cheque interface

The user confirmed that this update covers cheques only. Cash, purchases, expenses and other business accounts are outside this update. The reference spreadsheet inspired the information hierarchy; its financial records were not imported or reused.

## Screens

- **Home:** one incoming outstanding total and one outgoing outstanding total, followed by today, next-seven-day and overdue rows. Each row opens its matching cheque list. Add cheque remains visible at the top.
- **Cheques:** All / Incoming / Outgoing, shown count and shown sum, then a compact table. Name and cheque number form one column; amount and Gregorian due date form the other. Alternating row backgrounds and separators make scanning easier. Each row opens the full cheque details.
- **Add cheque:** direction, amount, due date, payer/payee and cheque number first. More details expands bank, branch, account reference, issue date and notes. Photos/scanning and custom reminder options have their own expansions. Existing optional values automatically appear when editing.
- **Filters and sort:** a single labelled menu contains the full filters, sort field, ascending/descending order and manual reordering. Direction changes preserve other filters. Reordering filtered results preserves hidden cheque positions.

Two aligned field groups keep four essential values readable on an iPhone. Accessibility text sizes switch to stacked labelled values; lists remain scrollable. Status text accompanies color: overdue/returned and collected/paid are readable without relying on color alone.

Cheque numbers remain text with leading zeros. Money retains exact currency precision. Passing the due date does not settle a cheque; confirmation still requests its actual payment or collection date. The data model and deployed iCloud schema are unchanged.

## Verification

The simulator UI suite checks essential fields without scrolling at normal text size, saving and reopening optional bank information, preservation of leading zeros, Arabic direction and language switching, incoming/outgoing filtering and the large-text row layout. Native screenshot and TestFlight results are recorded in [validation](VALIDATION.md). Signed-phone checks remain in [device acceptance](DEVICE_QA.md).

Build **1.0.0 (5)** passed all **58 distinct iPhone scenarios** and the separate 24-test macOS core suite in [run 37164184467](https://github.com/mf103871-boop/Shekati/actions/runs/37164184467). The signed build is available in the owner TestFlight group. Raw native screenshots were reviewed for [Arabic table](screenshots/native-build5-arabic-table.png), [Arabic entry](screenshots/native-build5-arabic-entry.png), [English table](screenshots/native-build5-english-table.png), [English detail](screenshots/native-build5-english-detail.png) and [accessibility text](screenshots/native-build5-large-text.png). All screenshot records are fictional.

The separate [browser preview](../Preview/index.html) uses fictional temporary data. Its count/sum updates, filters, search, optional entry, settlement, delete confirmation, language and dark contrast were checked at 375px and 320px. Browser illustrations are separate from native iPhone evidence.
