#!/usr/bin/env ruby
 

require 'aws-sdk-kms'
require 'aws-sdk'

client_kms = Aws::KMS::Client.new(profile: "labs-mfa", region: 'us-east-1')
client_s3 = Aws::S3::Client.new(profile: "labs-mfa", region: 'us-east-1')

in_file = File.open("./secret.txt", "r")
in_file_content = in_file.read
in_file.close

puts "Readable Text: " + in_file_content + "\n"

resp = client_kms.encrypt({
  key_id: ARGV[0],
  plaintext: in_file_content
})

this_data = resp.ciphertext_blob.unpack('H*')
this_file = File.new("./test-temp.txt", "w+")
this_file.puts(this_data)
this_bucket = ARGV[1]

puts "After Encrypt Object: " 
puts resp 
puts "\n"
puts "After Encrypt Object unpacked: "
puts this_data
puts "---Done\n"

# puts "Tests 1"
# puts "\n"
# puts this_data.pack("H*")
# puts this_data.class
# # puts this_data.pack("H*").class
# puts resp.ciphertext_blob
# puts resp.ciphertext_blob.class
# puts this_data.pack("H*")==resp.ciphertext_blob

response = client_s3.put_object(
    bucket: this_bucket,
    key: 'my-file.txt',
    body: this_file
  )

this_file.close
puts "S3 Put Object Complete"
puts "\n"

respi = client_s3.get_object({
    response_target: './test-dw.txt',
    bucket: this_bucket,
    key: 'my-file.txt' 
})

in_file = File.open("./test-dw.txt", "r")
in_file_content = in_file.read
# in_file.close


puts "Encrypted Data: "
puts "\n"
puts in_file_content

# puts this_data.inspect, [in_file_content.strip].inspect
# puts this_data.inspect==[in_file_content.strip].inspect
# puts this_data==[in_file_content.strip]
# puts this_data.methods
# puts "Tests 2"
# puts "\n"
# puts this_data, this_data.class, this_data.size
# puts "---Done\n"
# puts [in_file_content.strip], [in_file_content.strip].class, [in_file_content.strip].size
# puts "---Done\n"
# puts this_data==[in_file_content.strip]
# puts "---Done\n"
# puts this_data==in_file_content
# puts "---Done\n"
# puts [in_file_content.strip].pack("H*"), [in_file_content.strip].pack("H*").class, [in_file_content.strip].pack("H*").size
# puts "---Done\n"
# puts resp.ciphertext_blob, resp.ciphertext_blob.class, resp.ciphertext_blob.size
# puts "---Done\n"
# puts [in_file_content.strip].pack("H*")==resp.ciphertext_blob
# puts "---Done\n"

# puts in_file_content
# puts "\n"
# blob_packed = in_file_content.unpack("H*")
# puts blob_packed
# puts "\n"

# test_pack = test.pack("H*")

# puts resp.ciphertext_blob

# resp = client_kms.decrypt({
#   ciphertext_blob: resp.ciphertext_blob
# })

# puts 'Raw text: '
# puts resp.plaintext

resp = client_kms.decrypt({
  ciphertext_blob: [in_file_content.strip].pack("H*")
})

puts 'Raw text: '
puts resp.plaintext

final_file = File.new("./test-final.txt", "w")
final_file.puts(resp.plaintext)
final_file.close