require 'yaml'
require 'httparty'
require 'time'
require_relative 'bluesky'

# Load the YAML file
yaml_data = YAML.load_file('config.yml')

# Collect all blocked accounts and add them to each list
if yaml_data['accounts']
  accounts = yaml_data['accounts']
  muted_words = []
  labelers = []

  accounts.each do |name, account|
    email = account['email']
    password = account['password']

    begin
      # Initialize a Bluesky instance
      bluesky = Bluesky.new(email: email, password: password)
      puts "Fetching preferences for @#{name}…"
      preferences = bluesky.get_preferences["preferences"]
      muted_words += preferences.find { |p| p['$type'] == "app.bsky.actor.defs#mutedWordsPref" }&.dig("items") || []
      labelers += preferences.find { |p| p['$type'] == "app.bsky.actor.defs#labelersPref" }&.dig("labelers") || []

    rescue StandardError => e
      puts "Failed to process account #{name} (#{email}): #{e.message}"
    end
  end

  new_preferences = []
  new_preferences << {
    "$type": "app.bsky.actor.defs#mutedWordsPref",
    items: muted_words.uniq { |word| [word["value"], word["targets"], word["actorTarget"]] }
  }
  new_preferences << { "$type": "app.bsky.actor.defs#labelersPref", labelers: labelers.uniq }

  accounts.each do |name, account|
    email = account['email']
    password = account['password']

    begin
      # Initialize a Bluesky instance
      bluesky = Bluesky.new(email: email, password: password)
      preferences = bluesky.get_preferences["preferences"]
      preferences = preferences.reject { |p| ["app.bsky.actor.defs#mutedWordsPref", "app.bsky.actor.defs#labelersPref"].include?(p["$type"]) } + new_preferences
      puts "Saving preferences for @#{name}…"
      bluesky.set_preferences(preferences)

    rescue StandardError => e
      puts "Failed to process account #{name} (#{email}): #{e.message}"
    end
  end
else
  puts 'No accounts or lists found in the YAML file.'
end

