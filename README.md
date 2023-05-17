# notify-registration
Your Block Producer account can whitelist up to 3 other accounts to set up their own monitoring of the BP.
Each user can provide their own BotID and/or ChatID, and have their own notifications set up. 

The sensitive information (chatID & BotID) is encrypted with RSA-OAEP before being pushed onchain. 

## Get the current RSA Public Key:
```
curl -X POST 'https://api.waxsweden.org/v1/chain/get_table_rows' -H 'accept: application/json' -H 'Content-Type: application/json' -d '{ "code": "notify.se", "table": "config", "scope": "notify.se", "index_position": "", "key_type": "", "encode_type": "", "upper_bound": "", "lower_bound": "", "json":true }'
```

## Use the Web UI
You can set-up and manage your setup https://notify.waxsweden.org.

## Use the Script
Run the script ``` ./register.sh ``` and follow the instructions. More details is found in the FAQ.

You can edit chain API, cleos location and which contract to use in ``` config/chains.json ```

## FAQ
Full and up to date FAQ and guide can be found here: https://notify.waxsweden.org/faq
