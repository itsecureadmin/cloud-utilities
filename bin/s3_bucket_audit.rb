#!/usr/bin/env ruby

require 'rubygems'
require 'aws-sdk'
require 'optparse'

#
# read in required parameters:
# - region:  the AWS region
# - accounts:  the list of allowable accounts
# - debug:  optional, verbose printing / info
#
# ./s3_bucket_audit.rb -r us-east-1 -a ******,********,*******
#
# - this script runs and will identify s3 buckets with one of:
#   - string "global" in user or group ACL
#   - any principal of "*" without a Deny effect
#   - any principal with an account number not in the input list
#
#  RE:  http://docs.aws.amazon.com/sdkforruby/api/Aws/S3/Client.html
#
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: ./s3_bucket_audit.rb -r $AWS_REGION -a $AWS_ACCOUNT[,...] [-d]"

  opts.on("-k", "--accesskey ACCESSKEY", "AWS Access Key") do |k|
    options[:accesskey] = k
  end

  opts.on("-s", "--secretkey SECRETKEY", "AWS Secret Key") do |s|
    options[:secretkey] = s
  end

  opts.on("-r", "--region REGION", "AWS Region") do |r|
    options[:region] = r
  end

  opts.on("-a", "--accounts ACCOUNT", "Comma seperated list of allowable accounts.") do |a|
    options[:accounts] = a
  end

  opts.on("-x", "--exclusions EXCLUSION", "Comma seperated list of buckets to exclude from check.") do |x|
    options[:exclusions] = x
  end

  opts.on("-d", "--debug", "Enable debug") do |d|
    options[:debug] = d
  end
end.parse!

retry_count   = 0 
retry_success = 0 

accounts_array = options[:accounts].split(",")
buckets_with_violations = Hash.new

exclusions_array = Array.new
exclusions_array = options[:exclusions].split(",") if options[:exclusions]


if options[:accesskey] and options[:secretkey]
  puts "using provided credentials..."
  Aws.config.update({
    region: options[:region],
    credentials: Aws::Credentials.new(options[:accesskey],options[:secretkey]),
  })  
end # if options[:accesskey] and options[:secretkey]


while retry_success == 0
  retry_success = 1
  begin
    s3 = Aws::S3::Client.new(
      region: options[:region],
      credentials: Aws::Credentials.new(options[:accesskey],options[:secretkey]),
    )
  rescue Aws::S3::Errors::ThrottlingException => te
    sleep_time = ( 2 ** retry_count )
    retry_success = 0
    sleep sleep_time
    retry_count = retry_count + 1
  end # begin
end # while retry_success == 0

retry_count   = 0
retry_success = 0


while retry_success == 0
  retry_success = 1
  begin
    s3_list_buckets_response = s3.list_buckets({
    })
  rescue Aws::S3::Errors::ThrottlingException => te
    sleep_time = ( 2 ** retry_count )
    retry_success = 0
    sleep sleep_time
    retry_count = retry_count + 1
  end # begin
end # while retry_success == 0

s3_list_buckets_response.buckets.each do |bucket|

  puts ""                             if options[:debug]
  puts "bucket.name:  " + bucket.name if options[:debug]

  #
  # skip any bucket that is in the excluded list
  #
  if exclusions_array.include?(bucket.name)

    puts "skipping bucket as it is in the exclusion list:  #{bucket.name}"

  else

  #
  # get_bucket_acl
  #
  s3_get_bucket_acl_response = s3.get_bucket_acl({
    bucket: bucket.name,
    use_accelerate_endpoint: false,
  })

  s3_get_bucket_acl_response.grants.each do |grant|

#    puts grant.grantee.display_name
#    puts grant.grantee.email_address
#    puts grant.grantee.id
#    puts grant.grantee.type
#    puts grant.grantee.uri

    if grant.grantee.display_name
      display_name = grant.grantee.display_name
    elsif grant.grantee.uri
      display_name = grant.grantee.uri
    else
      display_name = "(none)"
    end

    puts "bucket ACLs (user,grant):"                                  if options[:debug]
    puts "  - " + display_name + "," + grant.permission if options[:debug]

    if /global/.match(grant.grantee.display_name) or /global/.match(grant.grantee.uri)
      if buckets_with_violations["#{bucket.name}"]
        buckets_with_violations["#{bucket.name}"] += 1
      else
        buckets_with_violations["#{bucket.name}"] = 1
      end
    end

  end

  #
  # get_bucket_policy
  #
  puts "bucket policies:  " if options[:debug]
  begin
    s3_get_bucket_policy_response = s3.get_bucket_policy({
      bucket: bucket.name,
      use_accelerate_endpoint: false,
    })
    s3_bucket_policy_hash = JSON.parse(s3_get_bucket_policy_response.policy.string)

    s3_bucket_policy_hash['Statement'].each do |statement|

      report_issue     = 0
      matching_account = 0

      #
      # 1. retrieve account #, if not '*'
      # 2. compare with list of allowable account numbers
      # 3. report if not in list
      #
      # if principal == '*' and effect is not 'Deny', report
      #
      puts "  statement.sid:       #{statement['Sid']}"    if options[:debug]
      puts "  statement.effect:    #{statement['Effect']}" if options[:debug]

      if statement['Principal'].eql?('*')
        if buckets_with_violations["#{bucket.name}"]
          buckets_with_violations["#{bucket.name}"] += 1 unless statement['Effect'].eql?('Deny')
        else
          buckets_with_violations["#{bucket.name}"]  = 1 unless statement['Effect'].eql?('Deny')
        end
        puts "  statement.principal: #{statement['Principal']}" if options[:debug]
      else

        if statement['Principal']

          puts "  statement.principals:" if options[:debug]
          principal  = statement['Principal']['AWS']
          principal_array = Array(principal)

          principal_array.each do |list_item|
            accounts_array.each do |account|
              if /#{account}/.match(list_item)
                puts "if matching" if options[:debug]
                puts "matching account (account - list_item):  #{account} - #{list_item}" if options[:debug]
                matching_account = 1
              else
                puts "if not matching" if options[:debug]
                puts "not matching account (account - list_item):  #{account} - #{list_item}" if options[:debug]
              end
            end
            puts "    - #{list_item}" if options[:debug]

            if matching_account < 1
              if buckets_with_violations["#{bucket.name}"]
                buckets_with_violations["#{bucket.name}"] += 1 unless statement['Effect'].eql?('Deny')
              else
                buckets_with_violations["#{bucket.name}"]  = 1 unless statement['Effect'].eql?('Deny')
              end
            end
            matching_account = 0
          end

        end # if statement['Principal']

      end

      action_array = Array(statement['Action'])
      puts "  statement.actions:"   if options[:debug]
      action_array.each do |action|
        puts "    - #{action}"      if options[:debug]
      end

      resource_array = Array(statement['Resource'])
      puts "  statement.resources:" if options[:debug]
      resource_array.each do |resource|
        puts "    - #{resource}"    if options[:debug]
      end

      condition_array = Array(statement['Condition'])
      puts "  statement.conditions:" if options[:debug]
      condition_array.each do |condition|
        puts "    - #{condition}"    if options[:debug]
      end

    end

  rescue Aws::S3::Errors::NoSuchBucketPolicy => nsbp
    puts "  - none" if options[:debug]
  end

  end # if exclusions_array.include?(bucket.name)

end # s3_list_buckets_response.buckets.each do |bucket|

buckets_with_violations.each do |key,value|
  puts "S3 Permission Violation:  #{key}:#{value}"
end

if buckets_with_violations.values.count > 0
  exit(1)
end
