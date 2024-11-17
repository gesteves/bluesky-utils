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
  # @param did [String] the DID of the user to unblock.
  # @return [Boolean] true if the block was successfully removed.
  # @raise [RuntimeError] if the request to remove the block fails.
  def unblock(did)
    profile = get_profile(did)
    blocking_uri = profile.dig("viewer", "blocking")

    return unless blocking_uri

    delete_record(blocking_uri)
  end

  # Adds a user to a specified list.
  #
  # @param did [String] the DID of the user to add.
  # @param url [String] the public URL of the list.
  # @return [Boolean] true if the user was successfully added.
  # @raise [RuntimeError] if the request to add the user fails.
  def add_user_to_list(did, url)
    uri = "at://#{@did}/app.bsky.graph.list/#{url.split("/").last}"

    record = {
      "$type" => "app.bsky.graph.listitem",
      "subject" => did,
      "list" => uri,
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
  # @param did [String] the DID of the profile to retrieve.
  # @return [Hash] the profile data.
  # @raise [RuntimeError] if the request to get the profile fails.
  def get_profile(did)
    response = HTTParty.get(
      "#{@base_url}/xrpc/app.bsky.actor.getProfile",
      headers: { "Authorization" => "Bearer #{@access_token}" },
      query: { "actor" => did }
    )

    if response.success?
      JSON.parse(response.body)
    else
      raise "Unable to retrieve profile for DID #{did}: #{response.body}"
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

  # Deletes a record given its at-uri.
  #
  # @param at_uri [String] the at-uri of the record to delete.
  # @raise [RuntimeError] if the request to delete the record fails.
  def delete_record(at_uri)
    segments = at_uri.split("/")
    rkey = segments.last
    collection = segments[-2]

    body = {
      "repo" => @did,
      "rkey" => rkey,
      "collection" => collection
    }

    response = HTTParty.post(
      "#{@base_url}/xrpc/com.atproto.repo.deleteRecord",
      body: body.to_json,
      headers: {
        "Authorization" => "Bearer #{@access_token}",
        "Content-Type" => "application/json"
      }
    )

    raise "Unable to delete record at #{at_uri}: #{response.body}" unless response.success?
  end
end
