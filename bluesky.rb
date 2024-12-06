require 'json'
require 'httparty'
require 'nokogiri'
require 'htmlentities'
require 'redcarpet'
require 'active_support/all'

class Bluesky
  attr_reader :did

  BASE_URL = "https://bsky.social".freeze

  # Initializes a new instance of the Bluesky class.
  #
  # @param email [String] the email for the Bluesky account.
  # @param password [String] the single-app password for the Bluesky account.
  def initialize(email:, password:)
    session = create_session(email: email, password: password)
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
        "#{BASE_URL}/xrpc/app.bsky.graph.getBlocks",
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
  def unblock(did)
    profile = get_profile(did)
    blocking_uri = profile.dig("viewer", "blocking")

    return unless blocking_uri

    delete_record(blocking_uri)
  end

  # Posts an article to Bluesky, creating a new post with optional text and embed data from a URL.
  #
  # @param url [String] The URL to embed in the post.
  # @param text [String, nil] Optional text to include in the post.
  # @param backdate_post [Boolean] Whether to backdate the post using the article:published_time OG meta tag.
  # @return [String, nil] The public Bluesky post URL, or nil if the post creation fails.
  def post_article(url:, text: nil, backdate_post: true)
    record_data = construct_article_record(url, text, backdate_post)
    return if record_data.nil?

    record = {
      repo: @did,
      collection: "app.bsky.feed.post",
      record: record_data
    }
    response = create_record(record)
    uri = response["uri"]

    if uri.start_with?("at://")
      components = uri.split("/")
      handle = components[2]
      post_id = components[-1]
      "https://bsky.app/profile/#{handle}/post/#{post_id}"
    else
      uri
    end
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
      "#{BASE_URL}/xrpc/com.atproto.repo.createRecord",
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
  def get_profile(did)
    response = HTTParty.get(
      "#{BASE_URL}/xrpc/app.bsky.actor.getProfile",
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

  # Creates a new session with the Bluesky API.
  #
  # @param email [String] the email for the Bluesky account.
  # @param password [String] the single-app password for the Bluesky account.
  # @return [Hash] the session data containing the DID and access token.
  def create_session(email:, password:)
    body = { identifier: email, password: password }

    response = HTTParty.post(
      "#{BASE_URL}/xrpc/com.atproto.server.createSession",
      body: body.to_json,
      headers: { "Content-Type" => "application/json" }
    )

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
      "#{BASE_URL}/xrpc/com.atproto.repo.deleteRecord",
      body: body.to_json,
      headers: {
        "Authorization" => "Bearer #{@access_token}",
        "Content-Type" => "application/json"
      }
    )

    raise "Unable to delete record at #{at_uri}: #{response.body}" unless response.success?
  end

  # Constructs a record for posting an article.
  #
  # @param url [String] The URL of the article.
  # @param text [String] The text content of the post.
  # @param backdate_post [Boolean] Whether to backdate the post using the article:published_time OG meta tag.
  # @return [Hash, nil] The record data, or nil if the required metadata is missing.
  def construct_article_record(url, text, backdate_post)
    html = Nokogiri::HTML(HTTParty.get(url).body)
    title = html.css("meta[property='og:title']")&.first&.[]("content")
    description = html.css("meta[property='og:description']")&.first&.[]("content")
    image_url = html.css("meta[property='og:image']")&.first&.[]("content")
    published_time = html.css("meta[property='article:published_time']")&.first&.[]("content")

    created_at = if backdate_post && published_time.present?
                   begin
                     parsed_time = DateTime.parse(published_time)
                     parsed_time < 1.day.ago ? parsed_time : Time.now
                   rescue
                     Time.now
                   end
                 else
                   Time.now
                 end

    return if title.blank? && description.blank?

    embed = {
      "$type" => "app.bsky.embed.external",
      "external" => {
        "uri" => url,
        "title" => title.presence,
        "description" => description.presence
      }.compact
    }

    if image_url.present?
      blob = upload_photo(image_url)["blob"]
      embed["external"]["thumb"] = blob if blob.present?
    end

    {
      text: smartypants(text),
      langs: ["en-US"],
      createdAt: created_at.iso8601,
      embed: embed
    }
  end

  # Uploads a photo to the Bluesky API and returns the response blob.
  #
  # @param url [String] The URL of the photo to upload.
  # @return [Hash] The response data for the uploaded blob.
  def upload_photo(url)
    image_data = HTTParty.get(url).body
    headers = {
      "Authorization" => "Bearer #{@access_token}",
      "Content-Type" => "image/jpeg"
    }

    response = HTTParty.post(
      "#{BASE_URL}/xrpc/com.atproto.repo.uploadBlob",
      body: image_data,
      headers: headers
    )

    if response.success?
      JSON.parse(response.body)
    else
      raise "Failed to upload photo: #{response.body}"
    end
  end

  # Creates a record in the Bluesky API for the specified collection.
  #
  # @param record [Hash] The record data to send to the API.
  # @return [Hash] The response data from the API.
  def create_record(record)
    headers = {
      "Authorization" => "Bearer #{@access_token}",
      "Content-Type" => "application/json"
    }

    response = HTTParty.post(
      "#{BASE_URL}/xrpc/com.atproto.repo.createRecord",
      body: record.to_json,
      headers: headers
    )

    if response.success?
      JSON.parse(response.body)
    else
      raise "Failed to create #{record[:collection]} record: #{response.body}"
    end
  end

  # Applies SmartyPants rendering to the provided text for typographic improvements.
  #
  # @param text [String] The text to process.
  # @return [String] The processed text, or an empty string if the input is blank.
  def smartypants(text)
    return "" if text.blank?

    HTMLEntities.new.decode(Redcarpet::Render::SmartyPants.render(text))
  end
end
