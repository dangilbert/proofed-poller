## Auth

- Uses cookie auth
- Probably login with username and password

## Polling

Request

```
curl 'https://app.proofreadmyessay.co.uk/freelance/freelancers/checkDocumentActivity?time=2020-07-03%2011:14:32' -H 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:77.0) Gecko/20100101 Firefox/77.0' -H 'Accept: application/json, text/javascript, */*; q=0.01' -H 'Accept-Language: en-US,en;q=0.5' --compressed -H 'X-CSRF-Token: f8f7d05ab2d3aff9088d1ea1bf12684d834544c6846f83c7a96e7af4fc3fd2af97a0c854bd276a8d0af470c6165acca73b3788377607ee9a7d05486d3b3edad0' -H 'X-Requested-With: XMLHttpRequest' -H 'DNT: 1' -H 'Connection: keep-alive' -H 'Referer: https://app.proofreadmyessay.co.uk/freelance/dashboard' -H 'Cookie: __cfduid=d67b0cc13f773284faa336c95e7676b801593774002; CAKEPHP=d0vv6k2fdhc5cf30v7aamkh4jo; csrfToken=f8f7d05ab2d3aff9088d1ea1bf12684d834544c6846f83c7a96e7af4fc3fd2af97a0c854bd276a8d0af470c6165acca73b3788377607ee9a7d05486d3b3edad0' -H 'TE: Trailers'
```

Change response
 `{"status":true,"message":"Change.","currentTime":"2020-07-03 11:17:33"}`

No change response
`{"status":false,"message":"No change.","currentTime":"2020-07-03 11:16:13"}`

Should we send the last received time?
How frequently polling

On change fetch the html and parse out the document

Send push notification using pushover with link to dashboard
