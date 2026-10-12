# Sakura Storage Center — quick guide

1. Fully shut down your Nintendo Switch before removing its microSD card.
2. Connect the microSD card to your Mac using a dedicated card reader. Nintendo Switch USB, DBI, or MTP connectivity is not a substitute for a card reader in Storage Center.
3. “Analysis” only reads metadata. “Backup” saves accessible card files to your Mac. “Restore” writes data to the selected card.
4. Do not disconnect storage while copying, performing SHA-256 verification, or restoring.
5. File-based backups include accessible files (including file-based emuMMC), but **not** hidden RAW emuMMC partitions or a bit-for-bit disk image.
6. Double-check the destination card before restoring; writing may change its contents.
