require 'rails_helper'
require_dependency 'theme_serializer'

describe Admin::ThemesController do
  let(:admin) { Fabricate(:admin) }

  it "is a subclass of AdminController" do
    expect(Admin::UsersController < Admin::AdminController).to eq(true)
  end

  before do
    sign_in(admin)
  end

  describe '#generate_key_pair' do
    it 'can generate key pairs' do
      post "/admin/themes/generate_key_pair.json"
      expect(response.status).to eq(200)
      json = JSON.parse(response.body)
      expect(json["private_key"]).to include("RSA PRIVATE KEY")
      expect(json["public_key"]).to include("ssh-rsa ")
    end
  end

  describe '#upload_asset' do
    let(:upload) do
      Rack::Test::UploadedFile.new(file_from_fixtures("fake.woff2", "woff2"))
    end

    it 'can create a theme upload' do
      post "/admin/themes/upload_asset.json", params: { file: upload }
      expect(response.status).to eq(201)

      upload = Upload.find_by(original_filename: "fake.woff2")

      expect(upload.id).not_to be_nil
      expect(JSON.parse(response.body)["upload_id"]).to eq(upload.id)
    end
  end

  describe '#export' do
    it "exports correctly" do
      theme = Fabricate(:theme, name: "Awesome Theme")
      theme.set_field(target: :common, name: :scss, value: '.body{color: black;}')
      theme.set_field(target: :desktop, name: :after_header, value: '<b>test</b>')
      theme.save!

      get "/admin/customize/themes/#{theme.id}/export"
      expect(response.status).to eq(200)

      # Save the output in a temp file (automatically cleaned up)
      file = Tempfile.new('archive.tar.gz')
      file.write(response.body)
      file.rewind
      uploaded_file = Rack::Test::UploadedFile.new(file.path, "application/x-gzip")

      # Now import it again
      expect do
        post "/admin/themes/import.json", params: { theme: uploaded_file }
        expect(response.status).to eq(201)
      end.to change { Theme.count }.by (1)

      json = ::JSON.parse(response.body)

      expect(json["theme"]["name"]).to eq("Awesome Theme")
      expect(json["theme"]["theme_fields"].length).to eq(2)
    end
  end

  describe '#import' do
    let(:theme_json_file) do
      Rack::Test::UploadedFile.new(file_from_fixtures("sam-s-simple-theme.dcstyle.json", "json"), "application/json")
    end

    let(:theme_archive) do
      Rack::Test::UploadedFile.new(file_from_fixtures("discourse-test-theme.tar.gz", "themes"), "application/x-gzip")
    end

    let(:image) do
      file_from_fixtures("logo.png")
    end

    it 'can import a theme from Git' do
      post "/admin/themes/import.json", params: {
        remote: '    https://github.com/discourse/discourse-brand-header       '
      }

      expect(response.status).to eq(201)
    end

    it 'imports a theme' do
      post "/admin/themes/import.json", params: { theme: theme_json_file }
      expect(response.status).to eq(201)

      json = ::JSON.parse(response.body)

      expect(json["theme"]["name"]).to eq("Sam's Simple Theme")
      expect(json["theme"]["theme_fields"].length).to eq(2)
      expect(UserHistory.where(action: UserHistory.actions[:change_theme]).count).to eq(1)
    end

    it 'imports a theme from an archive' do
      existing_theme = Fabricate(:theme, name: "Header Icons")

      expect do
        post "/admin/themes/import.json", params: { theme: theme_archive }
      end.to change { Theme.count }.by (1)
      expect(response.status).to eq(201)
      json = ::JSON.parse(response.body)

      expect(json["theme"]["name"]).to eq("Header Icons")
      expect(json["theme"]["theme_fields"].length).to eq(5)
      expect(UserHistory.where(action: UserHistory.actions[:change_theme]).count).to eq(1)
    end

    it 'updates an existing theme from an archive' do
      existing_theme = Fabricate(:theme, name: "Header Icons")

      expect do
        post "/admin/themes/import.json", params: { bundle: theme_archive }
      end.to change { Theme.count }.by (0)
      expect(response.status).to eq(201)
      json = ::JSON.parse(response.body)

      expect(json["theme"]["name"]).to eq("Header Icons")
      expect(json["theme"]["theme_fields"].length).to eq(5)
      expect(UserHistory.where(action: UserHistory.actions[:change_theme]).count).to eq(1)
    end
  end

  describe '#index' do
    it 'correctly returns themes' do
      ColorScheme.destroy_all
      Theme.destroy_all

      theme = Fabricate(:theme)
      theme.set_field(target: :common, name: :scss, value: '.body{color: black;}')
      theme.set_field(target: :desktop, name: :after_header, value: '<b>test</b>')

      theme.remote_theme = RemoteTheme.new(
        remote_url: 'awesome.git',
        remote_version: '7',
        local_version: '8',
        remote_updated_at: Time.zone.now
      )

      theme.save!

      # this will get serialized as well
      ColorScheme.create_from_base(name: "test", colors: [])

      get "/admin/themes.json"

      expect(response.status).to eq(200)

      json = ::JSON.parse(response.body)

      expect(json["extras"]["color_schemes"].length).to eq(2)
      theme_json = json["themes"].find { |t| t["id"] == theme.id }
      expect(theme_json["theme_fields"].length).to eq(2)
      expect(theme_json["remote_theme"]["remote_version"]).to eq("7")
    end
  end

  describe '#create' do
    it 'creates a theme' do
      post "/admin/themes.json", params: {
        theme: {
          name: 'my test name',
          theme_fields: [name: 'scss', target: 'common', value: 'body{color: red;}']
        }
      }

      expect(response.status).to eq(201)

      json = ::JSON.parse(response.body)

      expect(json["theme"]["theme_fields"].length).to eq(1)
      expect(UserHistory.where(action: UserHistory.actions[:change_theme]).count).to eq(1)
    end
  end

  describe '#update' do
    let(:theme) { Fabricate(:theme) }

    it 'can change default theme' do
      SiteSetting.default_theme_id = -1

      put "/admin/themes/#{theme.id}.json", params: {
        id: theme.id, theme: { default: true }
      }

      expect(response.status).to eq(200)
      expect(SiteSetting.default_theme_id).to eq(theme.id)
    end

    it 'can unset default theme' do
      SiteSetting.default_theme_id = theme.id

      put "/admin/themes/#{theme.id}.json", params: {
        theme: { default: false }
      }

      expect(response.status).to eq(200)
      expect(SiteSetting.default_theme_id).to eq(-1)
    end

    it 'updates a theme' do
      theme.set_field(target: :common, name: :scss, value: '.body{color: black;}')
      theme.save

      child_theme = Fabricate(:theme, component: true)

      upload = Fabricate(:upload)

      put "/admin/themes/#{theme.id}.json", params: {
        theme: {
          child_theme_ids: [child_theme.id],
          name: 'my test name',
          theme_fields: [
            { name: 'scss', target: 'common', value: '' },
            { name: 'scss', target: 'desktop', value: 'body{color: blue;}' },
            { name: 'bob', target: 'common', value: '', type_id: 2, upload_id: upload.id },
          ]
        }
      }

      expect(response.status).to eq(200)

      json = ::JSON.parse(response.body)

      fields = json["theme"]["theme_fields"].sort { |a, b| a["value"] <=> b["value"] }

      expect(fields[0]["value"]).to eq('')
      expect(fields[0]["upload_id"]).to eq(upload.id)
      expect(fields[1]["value"]).to eq('body{color: blue;}')
      expect(fields.length).to eq(2)
      expect(json["theme"]["child_themes"].length).to eq(1)
      expect(UserHistory.where(action: UserHistory.actions[:change_theme]).count).to eq(1)
    end

    it 'can update translations' do
      theme.set_field(target: :translations, name: :en, value: { en: { somegroup: { somestring: "defaultstring" } } }.deep_stringify_keys.to_yaml)
      theme.save!

      put "/admin/themes/#{theme.id}.json", params: {
        theme: {
          translations: {
            "somegroup.somestring" => "overridenstring"
          }
        }
      }

      # Response correct
      expect(response.status).to eq(200)
      json = ::JSON.parse(response.body)
      expect(json["theme"]["translations"][0]["value"]).to eq("overridenstring")

      # Database correct
      theme.reload
      expect(theme.theme_translation_overrides.count).to eq(1)
      expect(theme.theme_translation_overrides.first.translation_key).to eq("somegroup.somestring")

      # Set back to default
      put "/admin/themes/#{theme.id}.json", params: {
        theme: {
          translations: {
            "somegroup.somestring" => "defaultstring"
          }
        }
      }
      # Response correct
      expect(response.status).to eq(200)
      json = ::JSON.parse(response.body)
      expect(json["theme"]["translations"][0]["value"]).to eq("defaultstring")

      # Database correct
      theme.reload
      expect(theme.theme_translation_overrides.count).to eq(0)

    end

    it 'returns the right error message' do
      theme.update!(component: true)

      put "/admin/themes/#{theme.id}.json", params: {
        theme: { default: true }
      }

      expect(response.status).to eq(400)
      expect(JSON.parse(response.body)["errors"].first).to include(I18n.t("themes.errors.component_no_default"))
    end
  end

  describe '#destroy' do
    let(:theme) { Fabricate(:theme) }

    it "deletes the field's javascript cache" do
      theme.set_field(target: :common, name: :header, value: '<script>console.log("test")</script>')
      theme.save!

      javascript_cache = theme.theme_fields.find_by(target_id: Theme.targets[:common], name: :header).javascript_cache
      expect(javascript_cache).to_not eq(nil)

      delete "/admin/themes/#{theme.id}.json"

      expect(response.status).to eq(204)
      expect { theme.reload }.to raise_error(ActiveRecord::RecordNotFound)
      expect { javascript_cache.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
