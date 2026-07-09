require "test_helper"

class MediaTest < Minitest::Test
  def test_metadata_readers
    m = FlowChat::Media.new(
      {type: :image, mime_type: "image/jpeg", caption: "hi", filename: "a.jpg", id: "MID"},
      platform: :whatsapp
    )
    assert_equal :image, m.type
    assert_equal "image/jpeg", m.mime_type
    assert_equal "hi", m.caption
    assert_equal "a.jpg", m.filename
    assert_equal "MID", m.id
    assert_equal "image/jpeg", m[:mime_type]
  end

  def test_filename_falls_back_to_file_name_key
    m = FlowChat::Media.new({type: :document, file_name: "doc.pdf"}, platform: :telegram)
    assert_equal "doc.pdf", m.filename
  end

  def test_whatsapp_url_and_download_delegate_to_client
    client = Minitest::Mock.new
    client.expect(:get_media_url, "https://cdn/x.jpg", ["MID"])
    client.expect(:download_media, "BYTES", ["MID"])
    m = FlowChat::Media.new({type: :image, id: "MID"}, platform: :whatsapp, client: client)
    assert_equal "https://cdn/x.jpg", m.url
    assert_equal "BYTES", m.download
    client.verify
  end

  def test_telegram_url_and_download_delegate_to_client
    client = Minitest::Mock.new
    client.expect(:file_url, "https://tg/file.jpg", ["FID"])
    client.expect(:download_file, "TGBYTES", ["FID"])
    m = FlowChat::Media.new({type: :photo, file_id: "FID"}, platform: :telegram, client: client)
    assert_equal "https://tg/file.jpg", m.url
    assert_equal "TGBYTES", m.download
    client.verify
  end

  def test_url_based_platform_uses_direct_url
    m = FlowChat::Media.new({type: :image, url: "https://intercom/a.png"}, platform: :intercom)
    assert_equal "https://intercom/a.png", m.url
  end
end
