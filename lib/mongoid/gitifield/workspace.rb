require 'git'

module Mongoid
  module Gitifield
    class Workspace
      attr_reader :name, :path, :git

      def initialize(data: '', file_name: nil, folder_name: nil)
        @name = folder_name.presence || "gitifield-#{ DateTime.now.to_s(:nsec) }-#{ rand(10 ** 10).to_s.rjust(10,'0') }"
        @path = Pathname.new(Dir.tmpdir).join(@name)
        @bundle = Bundle.new(data, workspace: self)
        @file_name = file_name if file_name
        init_git_repo if @git.nil?
      end

      def update(data, date: nil, user: nil)
        init_git_repo if @git.nil?
        File.open(@path.join('content'), 'wb') do |file|
          file.write data
          file.fdatasync
        end
        @git.tap(&:add).commit_all('update')
        Commander.exec("git commit --amend --no-edit --date=\"#{ date.strftime('%a %b %e %T %Y +0000') }\"", path: @path) if date.present?
        Commander.exec("git commit --amend --no-edit --committer=\"#{ user.name } <#{ user.email }>\"", path: @path) if user.present?
      rescue Git::GitExecuteError
        nil
      end

      def init_git_repo(initial_commit: true)
        FileUtils::mkdir_p(@path)
        FileUtils.touch(@path.join('content'))

        new_repo = File.exists?(@path.join('.git')) != true
        @git = ::Git.init(@path.to_s, log: nil)
        @git.config('user.name', 'Philip Yu')
        @git.config('user.email', 'ht.yu@me.com')

        begin
          @git.tap(&:add).commit_all('initial commit') if new_repo && initial_commit
        rescue Git::GitExecuteError
          # Nothing to do (yet?)
        end
        @git.reset
        @path
      end

      def checkout(id)
        init_git_repo if @git.nil?
        @git.checkout(id)
        content
      end

      def revert(id)
        init_git_repo if @git.nil?
        @git.reset
        @git.checkout_file(id, 'content')
        begin
          @git.tap(&:add).commit_all("Revert to commit #{ id }")
        rescue Git::GitExecuteError
          # Nothing to do (yet?)
        end
      end

      def logs
        init_git_repo if @git.nil?
        @git.log.map {|l| { id: l.sha, date: l.date, message: l.message } }
      end

      def id
        logs.first.try(:[], :id)
      end

      def content
        init_git_repo if @git.nil?
        File.open(@path.join('content'), 'r') do |file|
          file.read
        end
      end

      # file_path be like /data/www/html/sa6.shoplinestg.com/current/aa.patch
      def apply_patch(patch_path)
        raise ApplyPatchError.new("Please make sure file exist!") unless File.exist?(patch_path)
        init_git_repo if @git.nil?

        before_apply(patch_path)
        @git.apply(@patch_name)
        after_apply

        true
      rescue Git::GitExecuteError
        false
      end

      def before_apply(patch_path)
        @patch_name = File.basename(patch_path)

        %x(cp #{patch_path} #{@path})

        @lc_file_path = @path.join(@file_name)
        FileUtils.touch(@lc_file_path)

        File.open(@lc_file_path, 'wb') do |file|
          file.puts content
          file.fdatasync
        end
        Dir.chdir(@path)
      end

      def after_apply
        File.open(@lc_file_path, 'r') do |file|
          update(file.read)
        end
      end

      def to_s
        init_git_repo if @git.nil?
        @git.reset
        @bundle.pack_up!
      end

      def clean
        @git = nil
        FileUtils.rm_rf(@path)
      end

      class ApplyPatchError < StandardError
      end
    end
  end
end
