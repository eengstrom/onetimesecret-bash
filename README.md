<!-- onetimesecret-bash -- easy visual editor: https://stackedit.io/editor# -->

## <a name="abstract"></a> Abstract
ots.bash is a bash-based command-line tool and API client for [One-Time Secret](https://onetimesecret.com/).  It provides easy, scriptable or command-line access to all features of One-Time Secret, plus a few extra tidbits.

## <a name="examples"></a> Examples

Simple command-line use cases:

* Share a secret, prompting for the secret from the terminal:

        ./ots share

* Share a secret, providing via STDIN or command line arguments:

        ./ots share --secret "this is super secret"

        ./ots share -- All remaining argments _are_ the secret

        ./ots share <<< "Something else super via HERESTRING"

        ./ots share <<-EOF
            This is a mulit-line secret via HEREDOC.
            Somthing else goes here.
        EOF

* Generate a random secret:

        ./ots generate

* Get/Retrieve a secret:

        ./ots get <key|url>
        ./ots retrieve <key|url>

* Use `--help` for complete list of command line actions

        ./ots --help

## <a name="apiusage"></a> API Usage

The same script can be sourced for it's functions so you may make use
of the OTS API via functions in your own script:

    # source for use anonymously (secrets created anonymously)
    source ots.bash

    # or, source with specific auth credentials
    APIUSER="USERNAME"
    APIKEY="APIKEY"
    source ots.bash -u $APIUSER -k $APIKEY

    # or specify / store them by function
    ots_set_host "https://onetimesecret.com"
    ots_set_user "USERNAME"
    ots_set_key  "APIKEY"

Then later in your script you can make use of the internal functions,
all of which begin `ots_`, as in:

    # check status of server
    ots_status

    # create a secret and get back the URL
    local URL=$(echo "secret" | ots_share)

    # share a multi line secret via HEREDOC.
    ots_share <<-EOF
    	This is a Secret
        ... on multiple lines
    EOF

    # fetch the secret data
    local DATA=$(ots_retrieve "$URL")

    # generate a new secret, and get back the private metadata key
    local KEY=$(ots_generate --private)

    # check on the current state of a secret, given the private key
    ots_state $KEY

    # burn a secret, given the private key
    ots_burn $KEY

For more examples, see also the `test.shunit` unit tests.

