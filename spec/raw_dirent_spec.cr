require "./spec_helper"

describe Dir::Walk do
  describe "raw_read_dir" do
    it "yields child names without dot entries" do
      with_ignore_files({"file.txt" => "contents"}) do |root|
        entries = {} of String => File::Type
        Dir::Walk.raw_read_dir(root) do |name, type|
          entries[name] = type
        end

        entries.keys.should eq(["file.txt"])
        expected_type = {% if flag?(:win32) %}
                          File::Type::Unknown
                        {% else %}
                          File::Type::File
                        {% end %}
        entries["file.txt"].should eq(expected_type)
      end
    end
  end
end
