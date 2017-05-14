<!-- onetimesecret-bash -- markdown visual editor: http://dillinger.io/ -->

## <a name="abstract"></a> Abstract
`ots.bash` is a bash-based command-line tool and API client for [One-Time Secret](https://onetimesecret.com/).  It provides easy, scriptable or command-line access to all features of One-Time Secret, plus a few extra tidbits.

## <a name="examples"></a> Examples

Simple command-line use cases:

* Share a secret, prompting for the secret from the terminal:

        ./ots share

* Share a secret, providing via STDIN or command line arguments:

        ./ots share --secret "this is super secret."

        ./ots share -- All remaining arguments after the '"--"' _are_ the secret.

        ./ots share <<< "Something else super secret via HERESTRING"

        ./ots share <<-EOF
            This is a mulit-line secret via HEREDOC.
            Somthing else goes here.
        EOF

    Note that while the script supports secrets on the command line, they are inherently less secure because anyone with access to the same machine could view them via `ps`, so `HEREDOC` or `HERESTRING` are better choices.

* Generate a random secret:

        ./ots generate

* Speciify options for shared or generated secrets:

        ./ots share ttl=600 \
                    passphrase="shared-secret" \
                    recipient="someone@somewhere.com" <<< "SECRET"
                    
    Note that any arguments not explicitly understood by the script are passed to the underlying action function (e.g. `share`), which in most cases are then simply passed to `curl`, so *caveat utilitor*.

* Get/Retrieve a secret:

        ./ots get <key|url>
        ./ots retrieve <key|url>

* Use `--help` for complete list of command line actions and known options:

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
    URL=ots_share <<-EOF
    	This is a Secret
        ... on multiple lines
    EOF

    # pass options to share or generate.
    URL=$(ots_share ttl=600 \
                    passphrase="shared-secret" \
                    recipient="someone@somewhere.com" <<< "SECRET")

    # fetch the secret data
    local DATA="$(ots_retrieve "$URL")"

    # share/generate a new secret, and get back the private metadata key
    local KEY=$(ots_metashare <<< "SECRET")
    local KEY=$(ots_metagenerate)

    # get a list of private metadata keys recently created.
    # note that this requires valid autnentication credentials
    local -a RECENT=( $(ots_recent) )

    # check on the current state of a secret, given the private key
    ots_state $KEY

    # burn a secret, given the private key
    ots_burn $KEY

For lots more examples, see also the `test.shunit` unit tests script.

