#!/usr/bin/env ruby
require 'yaml'
require_relative 'bluesky' # Adjust this path if the Bluesky class is in a different directory

# Prompt for user input
def prompt(message)
  print "#{message}: "
  gets.chomp
end

# Load configuration from YAML file
def load_config
  YAML.load_file('config.yml')
rescue Errno::ENOENT
  puts "Configuration file not found. Please create a 'config.yml' file."
  exit
end

# Main script
begin
  config = load_config

  puts "Welcome to the Bluesky Article Poster!"

  # Ask for account name
  account_name = prompt("Enter the account name (or leave blank to enter email/password manually)")

  if account_name.strip.empty?
    # Ask for email and password if no account name provided
    email = prompt("Enter your Bluesky account email")
    password = prompt("Enter your Bluesky account password")
  else
    # Look up account in the configuration file
    account = config['accounts'][account_name]

    if account
      email = account['email']
      password = account['password']
    else
      puts "Account name not found in config. Please enter email and password manually."
      email = prompt("Enter your Bluesky account email")
      password = prompt("Enter your Bluesky account password")
    end
  end

  # Create a new instance of the Bluesky class
  bluesky = Bluesky.new(email: email, password: password)

  # Ask for the article URL
  url = prompt("Enter the URL of the article to share")

  # Ask if the post should be backdated
  backdate_input = prompt("Should the post be backdated? (yes/y/no/n, default: yes)")
  backdate_post = case backdate_input.strip.downcase
                  when 'no', 'n'
                    false
                  else
                    true
                  end

  # Ask for optional text to include with the post
  text = prompt("Enter optional text to include with the post (or leave blank)")

  # Post the article
  puts "Posting the article to Bluesky..."
  post_url = bluesky.post_article(url: url, text: text.empty? ? nil : text, backdate_post: backdate_post)

  # Output the resulting URL
  if post_url
    puts "The article was successfully posted! View it here:"
    puts post_url
  else
    puts "Failed to post the article. Please check your inputs and try again."
  end

rescue StandardError => e
  puts "An error occurred: #{e.message}"
end
