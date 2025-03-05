# KOReader Zettelgarden Plugin

A KOReader plugin that integrates with [Zettelgarden](https://github.com/NickSavage/Zettelgarden), allowing you to seamlessly capture and organize highlights and notes from your e-reader into your Zettelgarden knowledge base.

## Features

- Send highlights directly to Zettelgarden as cards
- Configure your Zettelgarden server connection
- Optional card ID and title input for each highlight
- Secure authentication with token management

## Installation

1. Copy the `zettelgarden.koplugin` directory to your KOReader plugins folder:
   ```
   /path/to/koreader/plugins/
   ```

2. Restart KOReader

## Configuration

1. Open KOReader
2. Go to the main menu
3. Navigate to "Zettelgarden" → "Settings" → "Configure Zettelgarden server"
4. Enter your:
   - Server URL
   - Email
   - Password

## Usage

1. Select text in any book
2. Choose "Send to Zettelgarden" from the highlight menu
3. Optionally add:
   - Card ID
   - Title
4. The selected text will be sent to your Zettelgarden instance as a new card

## Requirements

- KOReader installation
- Running [Zettelgarden](https://github.com/NickSavage/Zettelgarden) instance
- Network connection

## License

MIT License - See LICENSE file for details

## Links

- [Zettelgarden Project](https://github.com/NickSavage/Zettelgarden)
- [KOReader](https://github.com/koreader/koreader) 