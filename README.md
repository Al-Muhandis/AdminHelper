
# Description of the bot's work
The bot helps quickly and silently ban spammers. 
 
Group members notify administrators of spam messages themselves using the `/spam` command. 
The command should be sent in response to a spam message.

All administrators receive a copy of the inspected message with the ability to check whether the member has correctly pointed to the spam message. 
If it is indeed a spam message, the member's rating is increased. 
The bot can send a notification that the admins need to decide if it is a spammer, or notify the admins that the spammer is banned with the option to rollback, or even silently ban, 
if the likelihood of a ban is high enough based on some factors. The bot can also preventively ban spammers.
If the inspected message is incorrectly identified as a spam, the member's rating is downgraded.

In order for the bot to receive a list of administrators in a group or in case of deleting or adding a new one, it is necessary to send the `/update` command from any of the current administrators.
Due to the fact that these commands are instantly deleted by the bot itself in the group, reports and updates occur unnoticed by users

#Spam classifier
A spam classifier has been added to the bot (you can turn it off in the service config), 
which can be trained and used to automatically notify administrators (and in the case of high spam probability can be automatically to ban) about suspicious messages. 
The algorithm of the Naive Bayesian Classifier is used. 
In addition, messages in which the number of emojis exceeds the specified number can also be automatically marked as spam by this filter

# Architecture
The software implements the telegram bot as a web server in webhook mode

# Dependencies
- fp-telegram (Telegram bots API wrapper) https://github.com/Al-Muhandis/fp-telegram
- brook-telegram (Plugin for BrookFoFreePascal) https://github.com/Al-Muhandis/brook-telegram/
- BrookForFreePascal & BrookFramework (HTTP server) https://github.com/risoflora/brookfreepascal & https://github.com/risoflora/brookframework
- dOPF (ORM) https://github.com/risoflora/brookfreepascal/tree/main/plugins/dopf
Notes: BrookFreePascal can be used without BrookFramework in broker mode