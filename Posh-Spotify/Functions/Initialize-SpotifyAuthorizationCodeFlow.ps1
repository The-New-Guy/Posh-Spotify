<#

    The Initialize-SpotifyAuthorizationCodeFlow function is defined here.

#>

#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

#====================================================================================================================================================
#############################################
## Initialize-SpotifyAuthorizationCodeFlow ##
#############################################

#region Initialize-SpotifyAuthorizationCodeFlow

function Initialize-SpotifyAuthorizationCodeFlow {

    <#

        .SYNOPSIS

            Initializes a Spotify session using the Authorization Code Flow. If the user accepts and the authorization is successful an Access Token
            will be returned allowing API access to Spotify commands.

        .DESCRIPTION

            Initializes a Spotify session using the Authorization Code Flow. If the user accepts and the authorization is successful an Access Token
            will be returned allowing API access to Spotify commands. If the user declines or there is an error, null will be returned and an error
            written to the error stream.

            For details on the Authorization Code Flow see the following for details.

                https://developer.spotify.com/documentation/general/guides/authorization-guide/#authorization-code-flow

        .PARAMETER CallbackUrl

            The URI to redirect to after the user grants/denies permission. This URI needs to have been entered in the Redirect URI whitelist that you
            specified when you registered your application. The value of CallbackUrl here must exactly match one of the values you entered when you
            registered your application, including upper/lowercase, terminating slashes, etc.

        .PARAMETER State

            The state can be useful for correlating requests and responses. Because your CallbackUrl can be guessed, using a state value can increase
            your assurance that an incoming connection is the result of an authentication request. If you generate a random string or encode the hash
            of some client state (e.g., a cookie) in this state variable, you can validate the response to additionally ensure that the request and
            response originated in the same browser. This provides protection against attacks such as cross-site request forgery. See RFC-6749.

            By default, this command will generate a new GUID and use that as the state. If you wish no state parameter be sent to the Spotify API,
            use null or an empty string to disable the feature.

        .PARAMETER Scopes

            A list of scopes for which authorization is being requested.

            See the Spotify documentation for details: https://developer.spotify.com/documentation/general/guides/authorization-guide/#list-of-scopes

        .PARAMETER ShowDialog

            Whether or not to force the user to approve the app again if they’ve already done so. If false (default), a user who has already approved
            the application may be automatically redirected to the URI specified by CallbackUrl. If true, the user will not be automatically
            redirected and will have to approve the app again.

        .PARAMETER RefreshToken

            If an Access Token was retrieved previously and is now expired, a new Access Token can be retrieved by providing the Refresh Token here.
            Aside from SpotifyEnv, no other parameters may be specified along with this parameter as they are not valid for a token refresh operation.

        .PARAMETER SpotifyEnv

            A string matching a key in the Spotify environment configuration hashtable to be used when making Spotify API calls. If this parameter is
            not specified it will use the current default environment configuration.

            For details on environment configurations please see https://github.com/The-New-Guy/Posh-Spotify.

        .OUTPUTS

            NewGuy.PoshSpotify.AuthenticationToken

    #>

    [CmdletBinding(DefaultParameterSetName = 'AquireToken')]
    [OutputType('NewGuy.PoshSpotify.AuthenticationToken')]

    param([Parameter(ParameterSetName = 'AquireToken')] [string]$CallbackUrl = 'http://localhost:8080/callback/',
          [Parameter(ParameterSetName = 'AquireToken')] [string]$State = ((New-Guid).Guid -replace '-',''),
          [Parameter(ParameterSetName = 'AquireToken')] [string[]]$Scopes,
          [Parameter(ParameterSetName = 'AquireToken')] [switch]$ShowDialog,
          [Parameter(ParameterSetName = 'RefreshToken')] [string]$RefreshToken,
          [string]$SpotifyEnv = $script:SpotifyDefaultEnv)

    begin {

        # The authorization code need to obtain a access and refresh token.
        $AuthCode = $null

        # An object representing the response of this call. (Access Token, Refresh Token, etc.)
        [NewGuy.PoshSpotify.AuthenticationToken]$AuthObj = $null

    }

    process {

        # If we don't have a Refresh Token we must request access from the user.
        if ($PSCmdlet.ParameterSetName -eq 'AquireToken') {

            #region Get Authorization Code

            # If no CallbackUrl was given, see if there is an environment specific CallbackUrl, otherwise use the default above.
            if (($null -eq $PSBoundParameters['CallbakUrl']) -and ($null -ne $script:SpotifyEnvironmentInfo[$SpotifyEnv].CallbackUrl)) {
                $CallbackUrl = $script:SpotifyEnvironmentInfo[$SpotifyEnv].CallbackUrl
            }

            # If no Scopes were given, see if there is an environment specific set of scopes.
            if (($null -eq $PSBoundParameters['Scopes']) -and ($script:SpotifyEnvironmentInfo[$SpotifyEnv].DefaultScopes -gt 0)) {
                $Scopes = $script:SpotifyEnvironmentInfo[$SpotifyEnv].DefaultScopes
            }

            $spotifyAuthUrl = "https://$script:SpotifyAccountsApiHostname/authorize/"
            $spotifyAuthUrl += "?client_id=$($script:SpotifyEnvironmentInfo[$SpotifyEnv].ClientId)"
            $spotifyAuthUrl += '&response_type=code'
            $spotifyAuthUrl += "&redirect_uri=$([System.Uri]::EscapeDataString($CallbackUrl))"
            if ($Scopes.Count -gt 0) { $spotifyAuthUrl += "&scope=$($Scopes -join ' ')" }
            if ($State.Length -gt 0) { $spotifyAuthUrl += "&state=$State" }
            if ($ShowDialog) { $spotifyAuthUrl += '&show_dialog=true' }

            Write-Verbose 'Opening browser window for user authorization request...'

            Start-Process $spotifyAuthUrl

            # Start web server.
            $listener = New-Object System.Net.HttpListener
            $listener.Prefixes.Add($CallbackUrl)

            try {

                Write-Verbose "Listening for authorization response on URL : $CallbackUrl"

                Write-Warning "`n"
                Write-Warning 'Note that thread is blocked waiting for a request. You need to send a valid HTTP request to stop the listener cleanly.'
                Write-Warning "To stop the listener go to the follwing URL in your browser : ${CallbackUrl}?Exit=1"
                Write-Warning "`n"

                $listener.Start()
                if ($listener.IsListening) {

                    # Process received request.
                    $context = $listener.GetContext()
                    $Request = $context.Request
                    $Response = $context.Response

                    # Prepare response.
                    $responseBody = ''

                    if ($Request.QueryString['Exit'] -ne $null) {
                        $responseBody = '<html><h1>Bad Request</h1></html>'
                        $Response.StatusCode = 400
                        Write-Error 'Bad Request : Listener exit requested.'
                    }

                    # If needed check the state code to ensure everything is on the up and up.
                    elseif (($State.Length -gt 0) -and ($Request.QueryString['state'] -ne $State)) {
                        $responseBody = '<html><h1>Bad Request</h1></html>'
                        $Response.StatusCode = 400
                        Write-Error 'Bad Request : State does not match.'
                    }

                    # If there was an error, report it.
                    elseif ($Request.QueryString['error'].Length -gt 0) {
                        $responseBody = '<html><h1>Unauthorized</h1></html>'
                        $Response.StatusCode = 401
                        Write-Error "Authorization Error : $($Request.QueryString['error'])"
                    }

                    # No errors so far...grab the access code if present.
                    elseif ($Request.QueryString['code'].Length -gt 0) {
                        $AuthCode = $Request.QueryString['code']
                        if (($DebugPreference -eq 'Continue') -or ($DebugPreference -eq 'Inquire')) {
                            $responseBody = @"
<html>
    <h1>Application Registered</h1>
    <pre style="font-family: consolas;">
Code  : $AuthCode
State : $State
    </pre>
</html>
"@
                        } else { $responseBody = '<html><h1>Application Registered</h1></html>' }
                    }

                    # Throw error if no code exist.
                    else {
                        $responseBody = '<html><h1>Bad Request</h1></html>'
                        $Response.StatusCode = 400
                        Write-Error 'Bad Request : No access code found.'
                    }

                    # Return the HTML to the caller.
                    $buffer = [Text.Encoding]::UTF8.GetBytes($responseBody)
                    $Response.ContentLength64 = $buffer.length
                    $Response.OutputStream.Write($buffer, 0, $buffer.length)
                    $Response.Close()
                }
            } finally {
                $listener.Stop()
            }

            #endregion Get Authorization Code

            #region Get Access Token

            if ($AuthCode -eq $null) { throw 'No authorization code found in request.' }

            $params = @{
                code = $AuthCode
                grant_type = 'authorization_code'
                redirect_uri = $CallbackUrl
            }
            $authZRes = Invoke-SpotifyRequest -Method POST -Path '/api/token' -RequestType AccountsAPI -RequestBodyParameters $params -SpotifyEnv $SpotifyEnv

            $AuthObj = [NewGuy.PoshSpotify.AuthenticationToken]::new($authZRes)

            #endregion Get Access Token

        }

        # If we have a Refresh Token we should be able to get a new Access Token without user interaction.
        elseif ($PSCmdlet.ParameterSetName -eq 'RefreshToken') {

            #region Get Access Token

            $params = @{
                refresh_token = $RefreshToken
                grant_type = 'refresh_token'
            }
            $authZRes = Invoke-SpotifyRequest -Method POST -Path '/api/token' -RequestType AccountsAPI -RequestBodyParameters $params -SpotifyEnv $SpotifyEnv

            $AuthObj = [NewGuy.PoshSpotify.AuthenticationToken]::new($authZRes)

            # We don't get a new Refresh Token when doing a refresh operation so just save the one we already got.
            $AuthObj.RefreshToken = $RefreshToken

            #endregion Get Access Token

        }

        return $AuthObj

    }
}

Export-ModuleMember -Function 'Initialize-SpotifyAuthorizationCodeFlow'

#endregion Initialize-SpotifyAuthorizationCodeFlow

#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>