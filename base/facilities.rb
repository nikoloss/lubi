#coding=utf-8
require 'qiniu'

module Lubi
  module Facilities
    class MissArgErr < Exception
      def initialize key
        super("require arg \"#{key}\" was not found!")
      end
    end

    class Connection

      def establish opt={}
        #check params
        [:ak, :sk].each do |key|
          raise MissArgErr, key unless opt.has_key? key
        end
        #real qiniu establish
        Qiniu.establish_connection! access_key: opt[:ak], secret_key: opt[:sk]
      end

      def upload(localFilePath, keyName, bucketName)
        put_policy = Qiniu::Auth::PutPolicy.new(bucketName, keyName)
        uptoken = Qiniu::Auth.generate_uptoken put_policy
        code, result, response_headers = Qiniu::Storage.upload_with_token_2(
          uptoken,
          localFilePath,
          keyName,
          nil,
          bucket: bucketName)
      end

      def download(localFilePath, keyName, bucketName)
        code, resp = Qiniu::Storage.domains(bucketName)
        domain = resp[0]["domain"]
        primitive_url = "http://" << domain << "/"<< keyName
        download_url = Qiniu::Auth.authorize_download_url(primitive_url)
        system("wget", "-O", localFilePath, download_url)
      end

    end

  end
end
