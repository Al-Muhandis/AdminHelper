
# Description of the bot's work
The bot helps quickly ban spammers in groups. 
 
Group members notify administrators of spam messages themselves using the `/spam` command. 
The command should be sent in response to a spam message.
All administrators receive a copy of the inspected message with the ability to check whether the member has correctly pointed to the spam message. 
If it is indeed a spam message, the member's rating is increased. 
At a certain number of points, spam messages are automatically deleted without the administrators' approval. 
If the inspected message is incorrectly identified as a spam, the member's rating is downgraded.

# Architecture
The software implements the telegram bot as a web server in webhook mode

# Dependencies
- fp-telegram (Telegram bots API wrapper)
- brook-telegram (Plugin for BrookFoFreePascal)
- BrookForFreePascal & BrookFramework (HTTP server)
