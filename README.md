
# Description of the bot's work
The bot helps moderate posts and quickly ban spammers in groups. 
Group members themselves notify administrators about spam messages. 
All administrators receive a copy of the message with the ability to indicate whether the member has correctly pointed to the spam message. 
If it is indeed a spam message, the member's rating is increased. 
At a certain number of points, the message is automatically deleted without the administrators' approval. 
If the spam message is incorrectly identified as spam, the member's rating is downgraded

# Architecture
The software implements the telegram bot as a web server in webhook mode

# Dependencies
- fp-telegram (Telegram bots API wrapper)
- brook-telegram (Plugin for BrookFoFreePascal)
- BrookForFreePascal & BrookFramework (HTTP server)
