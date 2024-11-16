require 'json'

class Bluesky
  attr_reader :did

  # Initializes a new instance of the Bluesky class.
  #
  # @param base_url [String] the base URL of the Bluesky API.
  # @param email [String] the email for the Bluesky account.
  # @param password [String] the single-app password for the Bluesky account.
  def initialize(base_url: "https://bsky.social", email:, password:)
    @base_url = base_url
    @auth = {
      identifier: email,
      password: password
    }
    session = create_session
    @did = session["did"]
    @access_token = session["accessJwt"]
  end

  # Retrieves all the accounts the user has blocked.
  #
  # @return [Array<Hash>] the list of blocked accounts.
  def get_blocks
    blocks = []
    cursor = nil

    loop do
      response = HTTParty.get(
        "#{@base_url}/xrpc/app.bsky.graph.getBlocks",
        headers: { "Authorization" => "Bearer #{@access_token}" },
        query: cursor ? { cursor: cursor } : {}
      )

      if response.success?
        data = JSON.parse(response.body)
        blocks.concat(data["blocks"])
        cursor = data["cursor"]
        break unless cursor
      else
        raise "Unable to retrieve blocked DIDs: #{response.body}"
      end
    end

    blocks
  end

  # Unblocks a user for a specified DID.
  #
  # @param unblock_did [String] the DID of the user to unblock.
  # @return [Boolean] true if the block was successfully removed.
  # @raise [RuntimeError] if the request to remove the block fails.
  def unblock(unblock_did)
    profile = get_profile(unblock_did)
    blocking_uri = profile.dig("viewer", "blocking")

    return unless blocking_uri

    rkey = blocking_uri.split("/").last

    body = {
      "repo" => @did,
      "rkey" => rkey,
      "collection" => "app.bsky.graph.block"
    }

    response = HTTParty.post(
      "#{@base_url}/xrpc/com.atproto.repo.deleteRecord",
      body: body.to_json,
      headers: {
        "Authorization" => "Bearer #{@access_token}",
        "Content-Type" => "application/json"
      }
    )

    raise "Unable to remove block for DID #{unblock_did}: #{response.body}" unless response.success?
  end

  # Adds a user to a specified list.
  #
  # @param user_did [String] the DID of the user to add.
  # @param list_uri [String] the URI of the list.
  # @return [Boolean] true if the user was successfully added.
  # @raise [RuntimeError] if the request to add the user fails.
  def add_user_to_list(user_did, list_uri)
    record = {
      "$type" => "app.bsky.graph.listitem",
      "subject" => user_did,
      "list" => list_uri,
      "createdAt" => Time.now.utc.iso8601
    }

    body = {
      "repo" => @did,
      "collection" => "app.bsky.graph.listitem",
      "record" => record
    }

    response = HTTParty.post(
      "#{@base_url}/xrpc/com.atproto.repo.createRecord",
      body: body.to_json,
      headers: {
        "Authorization" => "Bearer #{@access_token}",
        "Content-Type" => "application/json"
      }
    )

    raise "Unable to add user to list: #{response.body}" unless response.success?
  end

  # Retrieves profile data for a given DID.
  #
  # @param profile_did [String] the DID of the profile to retrieve.
  # @return [Hash] the profile data.
  # @raise [RuntimeError] if the request to get the profile fails.
  def get_profile(profile_did)
    response = HTTParty.get(
      "#{@base_url}/xrpc/app.bsky.actor.getProfile",
      headers: { "Authorization" => "Bearer #{@access_token}" },
      query: { "actor" => profile_did }
    )

    if response.success?
      JSON.parse(response.body)
    else
      raise "Unable to retrieve profile for DID #{profile_did}: #{response.body}"
    end
  end

  private

  # Creates a new session with the Bluesky API and caches the DID and access token.
  #
  # @return [Hash] the response from the session creation request.
  # @raise [RuntimeError] if the session creation request fails.
  def create_session
    body = {
      identifier: @auth[:identifier],
      password: @auth[:password]
    }

    response = HTTParty.post("#{@base_url}/xrpc/com.atproto.server.createSession", body: body.to_json, headers: { "Content-Type" => "application/json" })
    if response.success?
      JSON.parse(response.body)
    else
      raise "Unable to create a new session."
    end
  end
end
