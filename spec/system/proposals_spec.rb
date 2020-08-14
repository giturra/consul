require "rails_helper"

describe "Proposals" do
  it_behaves_like "milestoneable", :proposal

  scenario "Disabled with a feature flag" do
    Setting["process.proposals"] = nil
    expect { visit proposals_path }.to raise_exception(FeatureFlags::FeatureDisabled)
  end

  context "Concerns" do
    it_behaves_like "notifiable in-app", :proposal
    it_behaves_like "relationable", Proposal
    it_behaves_like "remotely_translatable",
                    :proposal,
                    "proposals_path",
                    {}
    it_behaves_like "remotely_translatable",
                    :proposal,
                    "proposal_path",
                    { "id": "id" }
    it_behaves_like "flaggable", :proposal
  end

  context "Index" do
    before do
      Setting["feature.featured_proposals"] = true
      Setting["featured_proposals_number"] = 3
    end
    let!(:featured_proposals) { create_featured_proposals }

    scenario "Lists featured and regular proposals" do
      proposals = [create(:proposal), create(:proposal), create(:proposal)]

      visit proposals_path

      expect(page).to have_selector("#proposals .proposal-featured", count: 3)
      featured_proposals.each do |featured_proposal|
        within("#featured-proposals") do
          expect(page).to have_content featured_proposal.title
          expect(page).to have_css("a[href='#{proposal_path(featured_proposal)}']")
        end
      end

      expect(page).to have_selector("#proposals .proposal", count: 3)
      proposals.each do |proposal|
        within("#proposals") do
          expect(page).to have_content proposal.title
          expect(page).to have_content proposal.summary
          expect(page).to have_css("a[href='#{proposal_path(proposal)}']", text: proposal.title)
        end
      end
    end

    scenario "Index view mode" do
      proposals = [create(:proposal), create(:proposal), create(:proposal)]

      visit proposals_path

      click_button "View mode"

      click_link "List"

      proposals.each do |proposal|
        within("#proposals") do
          expect(page).to     have_link proposal.title
          expect(page).not_to have_content proposal.summary
        end
      end

      click_button "View mode"

      click_link "Cards"

      proposals.each do |proposal|
        within("#proposals") do
          expect(page).to have_link proposal.title
          expect(page).to have_content proposal.summary
        end
      end
    end

    scenario "Index view mode is not shown with selected filter" do
      visit proposals_path

      click_link "View selected proposals"

      expect(page).not_to have_selector(".view-mode")
      expect(page).not_to have_button("View mode")
    end

    scenario "Pagination" do
      per_page = 3
      allow(Proposal).to receive(:default_per_page).and_return(per_page)
      (per_page + 2).times { create(:proposal) }

      visit proposals_path

      expect(page).to have_selector("#proposals .proposal", count: per_page)

      within("ul.pagination") do
        expect(page).to have_content("1")
        expect(page).to have_link("2", href: "/proposals?page=2")
        expect(page).not_to have_content("3")
        click_link "Next", exact: false
      end

      expect(page).to have_selector("#proposals .proposal-featured", count: 3)
      expect(page).to have_selector("#proposals .proposal", count: 2)
    end

    scenario "Index should show proposal descriptive image only when is defined" do
      proposal = create(:proposal)
      proposal_with_image = create(:proposal, :with_image)

      visit proposals_path

      within("#proposal_#{proposal.id}") do
        expect(page).not_to have_css("div.with-image")
      end
      within("#proposal_#{proposal_with_image.id}") do
        expect(page).to have_css("img[alt='#{proposal_with_image.image.title}']")
      end
    end
  end

  scenario "Show" do
    proposal = create(:proposal)

    visit proposal_path(proposal)

    expect(page).to have_content proposal.title
    expect(page).to have_content proposal.code
    expect(page).to have_content "Proposal description"
    expect(page).to have_content proposal.author.name
    expect(page).to have_content I18n.l(proposal.created_at.to_date)
    expect(page).to have_selector(avatar(proposal.author.name))
    expect(page.html).to include "<title>#{proposal.title}</title>"
    expect(page).not_to have_selector ".js-flag-actions"
    expect(page).not_to have_selector ".js-follow"

    within(".social-share-button") do
      expect(page.all("a").count).to be(3) # Twitter, Facebook, Telegram
    end
  end

  context "Show" do
    scenario "When path matches the friendly url" do
      proposal = create(:proposal)

      right_path = proposal_path(proposal)
      visit right_path

      expect(page).to have_current_path(right_path)
    end

    scenario "When path does not match the friendly url" do
      proposal = create(:proposal)

      right_path = proposal_path(proposal)
      old_path = "#{proposals_path}/#{proposal.id}-something-else"
      visit old_path

      expect(page).not_to have_current_path(old_path)
      expect(page).to have_current_path(right_path)
    end

    scenario "Can access the community" do
      Setting["feature.community"] = true

      proposal = create(:proposal)
      visit proposal_path(proposal)
      expect(page).to have_content "Access the community"

      Setting["feature.community"] = false
    end

    scenario "Can not access the community" do
      Setting["feature.community"] = false

      proposal = create(:proposal)
      visit proposal_path(proposal)
      expect(page).not_to have_content "Access the community"
    end

    scenario "Selected proposals does not show all information" do
      proposal = create(:proposal, :selected)
      login_as(create(:user))

      visit proposal_path(proposal)
      expect(page).not_to have_content proposal.code
      expect(page).not_to have_content("Proposal code:")

      expect(page).not_to have_content("Related content")
      expect(page).not_to have_button("Add related content")

      within(".proposal-info") do
        expect(page).not_to have_link("No comments", href: "#comments")
      end
    end

    scenario "After using the browser's back button, social buttons will have one screen reader", :js do
      proposal = create(:proposal)
      visit proposal_path(proposal)
      click_link "Help"

      expect(page).to have_content "CONSUL is a platform for citizen participation"

      go_back

      expect(page).to have_css "span.show-for-sr", text: "twitter", count: 1
    end
  end

  describe "Show sticky support button on mobile screens", :js do
    let!(:window_size) { Capybara.current_window.size }

    before do
      Capybara.current_window.resize_to(640, 480)
    end

    after do
      Capybara.current_window.resize_to(*window_size)
    end

    scenario "On a first visit" do
      proposal = create(:proposal)
      visit proposal_path(proposal)

      within("#proposal_sticky") do
        expect(page).to have_css(".is-stuck")
        expect(page).not_to have_css(".is-anchored")
      end
    end

    scenario "After visiting another page" do
      proposal = create(:proposal)

      visit proposal_path(proposal)
      click_link "Go back"
      click_link proposal.title

      within("#proposal_sticky") do
        expect(page).to have_css(".is-stuck")
        expect(page).not_to have_css(".is-anchored")
      end
    end

    scenario "After using the browser's back button" do
      proposal = create(:proposal)

      visit proposal_path(proposal)
      click_link "Go back"

      expect(page).to have_link proposal.title

      go_back

      within("#proposal_sticky") do
        expect(page).to have_css(".is-stuck")
        expect(page).not_to have_css(".is-anchored")
      end
    end

    scenario "After using the browser's forward button" do
      proposal = create(:proposal)

      visit proposals_path
      click_link proposal.title

      expect(page).not_to have_link proposal.title

      go_back

      expect(page).to have_link proposal.title

      go_forward

      within("#proposal_sticky") do
        expect(page).to have_css(".is-stuck")
        expect(page).not_to have_css(".is-anchored")
      end
    end
  end

  context "Embedded video" do
    scenario "Show YouTube video" do
      proposal = create(:proposal, video_url: "http://www.youtube.com/watch?v=a7UFm6ErMPU")
      visit proposal_path(proposal)
      expect(page).to have_selector("div[id='js-embedded-video']")
      expect(page.html).to include "https://www.youtube.com/embed/a7UFm6ErMPU"
    end

    scenario "Show Vimeo video" do
      proposal = create(:proposal, video_url: "https://vimeo.com/7232823")
      visit proposal_path(proposal)
      expect(page).to have_selector("div[id='js-embedded-video']")
      expect(page.html).to include "https://player.vimeo.com/video/7232823"
    end

    scenario "Dont show video" do
      proposal = create(:proposal, video_url: nil)

      visit proposal_path(proposal)
      expect(page).not_to have_selector("div[id='js-embedded-video']")
    end
  end

  scenario "Social Media Cards" do
    proposal = create(:proposal)

    visit proposal_path(proposal)
    expect(page).to have_css "meta[name='twitter:title'][content=\'#{proposal.title}\']", visible: false
    expect(page).to have_css "meta[property='og:title'][content=\'#{proposal.title}\']", visible: false
  end

  scenario "Create and publish" do
    author = create(:user)
    login_as(author)

    visit new_proposal_path

    fill_in "Proposal title", with: "Help refugees"
    fill_in "Proposal summary", with: "In summary, what we want is..."
    fill_in "Proposal text", with: "This is very important because..."
    fill_in "proposal_video_url", with: "https://www.youtube.com/watch?v=yPQfcG-eimk"
    fill_in "proposal_responsible_name", with: "Isabel Garcia"
    fill_in "proposal_tag_list", with: "Refugees, Solidarity"
    check "proposal_terms_of_service"

    click_button "Create proposal"

    expect(page).to have_content "Proposal created successfully."
    expect(page).to have_content "Help refugees"
    expect(page).not_to have_content "You can also see more information about improving your campaign"

    click_link "No, I want to publish the proposal"

    expect(page).to have_content "Improve your campaign and get more support"
    click_link "Not now, go to my proposal"

    expect(page).to have_content "Help refugees"
    expect(page).to have_content "In summary, what we want is..."
    expect(page).to have_content "This is very important because..."
    expect(page).to have_content "https://www.youtube.com/watch?v=yPQfcG-eimk"
    expect(page).to have_content author.name
    expect(page).to have_content "Refugees"
    expect(page).to have_content "Solidarity"
    expect(page).to have_content I18n.l(Proposal.last.created_at.to_date)
  end

  scenario "Create with invisible_captcha honeypot field" do
    author = create(:user)
    login_as(author)

    visit new_proposal_path
    fill_in "Proposal title", with: "I am a bot"
    fill_in "proposal_subtitle", with: "This is the honeypot field"
    fill_in "Proposal summary", with: "This is the summary"
    fill_in "Proposal text", with: "This is the description"
    fill_in "proposal_responsible_name", with: "Some other robot"
    check "proposal_terms_of_service"

    click_button "Create proposal"

    expect(page.status_code).to eq(200)
    expect(page.html).to be_empty
    expect(page).to have_current_path(proposals_path)
  end

  scenario "Create proposal too fast" do
    allow(InvisibleCaptcha).to receive(:timestamp_threshold).and_return(Float::INFINITY)

    author = create(:user)
    login_as(author)

    visit new_proposal_path
    fill_in "Proposal title", with: "I am a bot"
    fill_in "Proposal summary", with: "This is the summary"
    fill_in "Proposal text", with: "This is the description"
    fill_in "proposal_responsible_name", with: "Some other robot"
    check "proposal_terms_of_service"

    click_button "Create proposal"

    expect(page).to have_content "Sorry, that was too quick! Please resubmit"

    expect(page).to have_current_path(new_proposal_path)
  end

  scenario "Responsible name is stored for anonymous users" do
    author = create(:user)
    login_as(author)

    visit new_proposal_path
    fill_in "Proposal title", with: "Help refugees"
    fill_in "Proposal summary", with: "In summary, what we want is..."
    fill_in "Proposal text", with: "This is very important because..."
    fill_in "proposal_responsible_name", with: "Isabel Garcia"
    fill_in "proposal_responsible_name", with: "Isabel Garcia"
    check "proposal_terms_of_service"

    click_button "Create proposal"

    expect(page).to have_content "Proposal created successfully."
    click_link "No, I want to publish the proposal"
    click_link "Not now, go to my proposal"

    expect(Proposal.last.responsible_name).to eq("Isabel Garcia")
  end

  scenario "Responsible name field is not shown for verified users" do
    author = create(:user, :level_two)
    login_as(author)

    visit new_proposal_path
    expect(page).not_to have_selector("#proposal_responsible_name")

    fill_in "Proposal title", with: "Help refugees"
    fill_in "Proposal summary", with: "In summary, what we want is..."
    fill_in "Proposal text", with: "This is very important because..."
    check "proposal_terms_of_service"

    click_button "Create proposal"
    expect(page).to have_content "Proposal created successfully."
    click_link "No, I want to publish the proposal"
    click_link "Not now, go to my proposal"

    expect(Proposal.last.responsible_name).to eq(author.document_number)
  end

  scenario "Errors on create" do
    author = create(:user)
    login_as(author)

    visit new_proposal_path
    click_button "Create proposal"

    expect(page).to have_content error_message
  end

  scenario "JS injection is prevented but safe html is respected" do
    author = create(:user)
    login_as(author)

    visit new_proposal_path
    fill_in "Proposal title", with: "Testing an attack"
    fill_in "Proposal summary", with: "In summary, what we want is..."
    fill_in "Proposal text", with: "<p>This is <script>alert('an attack');</script></p>"
    fill_in "proposal_responsible_name", with: "Isabel Garcia"
    check "proposal_terms_of_service"

    click_button "Create proposal"

    expect(page).to have_content "Proposal created successfully."
    click_link "No, I want to publish the proposal"
    click_link "Not now, go to my proposal"

    expect(page).to have_content "Testing an attack"
    expect(page.html).to include "<p>This is alert('an attack');</p>"
    expect(page.html).not_to include "<script>alert('an attack');</script>"
    expect(page.html).not_to include "&lt;p&gt;This is"
  end

  scenario "Autolinking is applied to description" do
    author = create(:user)
    login_as(author)

    visit new_proposal_path
    fill_in "Proposal title", with: "Testing auto link"
    fill_in "Proposal summary", with: "In summary, what we want is..."
    fill_in "Proposal text", with: "<p>This is a link www.example.org</p>"
    fill_in "proposal_responsible_name", with: "Isabel Garcia"
    check "proposal_terms_of_service"

    click_button "Create proposal"

    expect(page).to have_content "Proposal created successfully."
    click_link "No, I want to publish the proposal"
    click_link "Not now, go to my proposal"

    expect(page).to have_content "Testing auto link"
    expect(page).to have_link("www.example.org", href: "http://www.example.org")
  end

  scenario "JS injection is prevented but autolinking is respected" do
    author = create(:user)
    js_injection_string = "<script>alert('hey')</script> <a href=\"javascript:alert('surprise!')\">click me<a/> http://example.org"
    login_as(author)

    visit new_proposal_path
    fill_in "Proposal title", with: "Testing auto link"
    fill_in "Proposal summary", with: "In summary, what we want is..."
    fill_in "Proposal text", with: js_injection_string
    fill_in "proposal_responsible_name", with: "Isabel Garcia"
    check "proposal_terms_of_service"

    click_button "Create proposal"

    expect(page).to have_content "Proposal created successfully."
    click_link "No, I want to publish the proposal"
    click_link "Not now, go to my proposal"

    expect(page).to have_content "Testing auto link"
    expect(page).to have_link("http://example.org", href: "http://example.org")
    expect(page).not_to have_link("click me")
    expect(page.html).not_to include "<script>alert('hey')</script>"

    click_link "Dashboard"

    within "#side_menu" do
      click_link "Edit my proposal"
    end

    click_link "Edit proposal"

    expect(page).to have_current_path(edit_proposal_path(Proposal.last))
    expect(page).not_to have_link("click me")
    expect(page.html).not_to include "<script>alert('hey')</script>"
  end

  context "Geozones" do
    scenario "Default whole city" do
      author = create(:user)
      login_as(author)

      visit new_proposal_path
      fill_in_proposal

      click_button "Create proposal"

      expect(page).to have_content "Proposal created successfully."
      click_link "No, I want to publish the proposal"
      click_link "Not now, go to my proposal"

      within "#geozone" do
        expect(page).to have_content "All city"
      end
    end

    scenario "Specific geozone" do
      create(:geozone, name: "California")
      create(:geozone, name: "New York")
      login_as(create(:user))

      visit new_proposal_path

      fill_in "Proposal title", with: "Help refugees"
      fill_in "Proposal summary", with: "In summary, what we want is..."
      fill_in "Proposal text", with: "This is very important because..."
      fill_in "proposal_video_url", with: "https://www.youtube.com/watch?v=yPQfcG-eimk"
      fill_in "proposal_responsible_name", with: "Isabel Garcia"
      check "proposal_terms_of_service"

      select("California", from: "proposal_geozone_id")
      click_button "Create proposal"

      expect(page).to have_content "Proposal created successfully."
      click_link "No, I want to publish the proposal"
      click_link "Not now, go to my proposal"

      within "#geozone" do
        expect(page).to have_content "California"
      end
    end
  end

  context "Retired proposals" do
    scenario "Retire" do
      proposal = create(:proposal)
      login_as(proposal.author)

      visit user_path(proposal.author)
      within("#proposal_#{proposal.id}") do
        click_link "Dashboard"
      end

      within "#side_menu" do
        click_link "Edit my proposal"
      end

      click_link "Retire proposal"

      expect(page).to have_current_path(retire_form_proposal_path(proposal))

      select "Duplicated", from: "proposal_retired_reason"
      fill_in "Explanation", with: "There are three other better proposals with the same subject"
      click_button "Retire proposal"

      expect(page).to have_content "Proposal retired"

      visit proposal_path(proposal)

      expect(page).to have_content proposal.title
      expect(page).to have_content "Proposal retired by the author"
      expect(page).to have_content "Duplicated"
      expect(page).to have_content "There are three other better proposals with the same subject"
    end

    scenario "Fields are mandatory", :js do
      proposal = create(:proposal)
      login_as(proposal.author)

      visit retire_form_proposal_path(proposal)

      click_button "Retire proposal"

      expect(page).not_to have_content "Proposal retired"
      expect(page).to have_content "can't be blank", count: 2
    end

    scenario "Index do not list retired proposals by default" do
      Setting["feature.featured_proposals"] = true
      create_featured_proposals
      not_retired = create(:proposal)
      retired = create(:proposal, :retired)

      visit proposals_path

      expect(page).to have_selector("#proposals .proposal", count: 1)
      within("#proposals") do
        expect(page).to have_content not_retired.title
        expect(page).not_to have_content retired.title
      end
    end

    scenario "Index has a link to retired proposals list" do
      not_retired = create(:proposal)
      retired = create(:proposal, :retired)

      visit proposals_path

      expect(page).not_to have_content retired.title
      click_link "Proposals retired by the author"

      expect(page).to have_content retired.title
      expect(page).not_to have_content not_retired.title
    end

    scenario "Retired proposals index interface elements" do
      visit proposals_path(retired: "all")

      expect(page).not_to have_content "Advanced search"
      expect(page).not_to have_content "Categories"
      expect(page).not_to have_content "Districts"
    end

    scenario "Retired proposals index has links to filter by retired_reason" do
      unfeasible = create(:proposal, :retired, retired_reason: "unfeasible")
      duplicated = create(:proposal, :retired, retired_reason: "duplicated")

      visit proposals_path(retired: "all")

      expect(page).to have_content unfeasible.title
      expect(page).to have_content duplicated.title
      expect(page).to have_link "Duplicated"
      expect(page).to have_link "Underway"
      expect(page).to have_link "Unfeasible"
      expect(page).to have_link "Done"
      expect(page).to have_link "Other"

      click_link "Unfeasible"

      expect(page).to have_content unfeasible.title
      expect(page).not_to have_content duplicated.title
    end

    context "Special interface translation behaviour" do
      before { Setting["feature.translation_interface"] = true }

      scenario "Cant manage translations" do
        proposal = create(:proposal)
        login_as(proposal.author)

        visit retire_form_proposal_path(proposal)

        expect(page).not_to have_css "#add_language"
        expect(page).not_to have_link "Remove language"
      end
    end
  end

  scenario "Update should not be posible if logged user is not the author" do
    proposal = create(:proposal)
    expect(proposal).to be_editable
    login_as(create(:user))

    visit edit_proposal_path(proposal)
    expect(page).not_to have_current_path(edit_proposal_path(proposal))
    expect(page).to have_current_path(root_path)
    expect(page).to have_content "You do not have permission"
  end

  scenario "Update should not be posible if proposal is not editable" do
    Setting["max_votes_for_proposal_edit"] = 3
    proposal = create(:proposal, voters: Array.new(4) { create(:user) })

    expect(proposal).not_to be_editable

    login_as(proposal.author)
    visit edit_proposal_path(proposal)

    expect(page).not_to have_current_path(edit_proposal_path(proposal))
    expect(page).to have_current_path(root_path)
    expect(page).to have_content "You do not have permission"
    Setting["max_votes_for_proposal_edit"] = 1000
  end

  scenario "Update should be posible for the author of an editable proposal" do
    proposal = create(:proposal)
    login_as(proposal.author)

    visit edit_proposal_path(proposal)
    expect(page).to have_current_path(edit_proposal_path(proposal))

    fill_in "Proposal title", with: "End child poverty"
    fill_in "Proposal summary", with: "Basically..."
    fill_in "Proposal text", with: "Let's do something to end child poverty"
    fill_in "proposal_responsible_name", with: "Isabel Garcia"

    click_button "Save changes"

    expect(page).to have_content "Proposal updated successfully."
    expect(page).to have_content "Basically..."
    expect(page).to have_content "End child poverty"
    expect(page).to have_content "Let's do something to end child poverty"
  end

  scenario "Errors on update" do
    proposal = create(:proposal)
    login_as(proposal.author)

    visit edit_proposal_path(proposal)
    fill_in "Proposal title", with: ""
    click_button "Save changes"

    expect(page).to have_content error_message
  end

  describe "Proposal index order filters" do
    scenario "Default order is hot_score", :js do
      best_proposal = create(:proposal, title: "Best proposal")
      best_proposal.update_column(:hot_score, 10)
      worst_proposal = create(:proposal, title: "Worst proposal")
      worst_proposal.update_column(:hot_score, 2)
      medium_proposal = create(:proposal, title: "Medium proposal")
      medium_proposal.update_column(:hot_score, 5)

      visit proposals_path

      expect(best_proposal.title).to appear_before(medium_proposal.title)
      expect(medium_proposal.title).to appear_before(worst_proposal.title)
    end

    scenario "Proposals are ordered by confidence_score", :js do
      best_proposal = create(:proposal, title: "Best proposal")
      best_proposal.update_column(:confidence_score, 10)
      worst_proposal = create(:proposal, title: "Worst proposal")
      worst_proposal.update_column(:confidence_score, 2)
      medium_proposal = create(:proposal, title: "Medium proposal")
      medium_proposal.update_column(:confidence_score, 5)

      visit proposals_path
      click_link "highest rated"
      expect(page).to have_selector("a.is-active", text: "highest rated")

      within "#proposals" do
        expect(best_proposal.title).to appear_before(medium_proposal.title)
        expect(medium_proposal.title).to appear_before(worst_proposal.title)
      end

      expect(current_url).to include("order=confidence_score")
      expect(current_url).to include("page=1")
    end

    scenario "Proposals are ordered by newest", :js do
      best_proposal = create(:proposal, title: "Best proposal", created_at: Time.current)
      medium_proposal = create(:proposal, title: "Medium proposal", created_at: Time.current - 1.hour)
      worst_proposal = create(:proposal, title: "Worst proposal", created_at: Time.current - 1.day)

      visit proposals_path
      click_link "newest"
      expect(page).to have_selector("a.is-active", text: "newest")

      within "#proposals" do
        expect(best_proposal.title).to appear_before(medium_proposal.title)
        expect(medium_proposal.title).to appear_before(worst_proposal.title)
      end

      expect(current_url).to include("order=created_at")
      expect(current_url).to include("page=1")
    end

    context "Recommendations" do
      let!(:best_proposal)   { create(:proposal, title: "Best",   cached_votes_up: 10, tag_list: "Sport") }
      let!(:medium_proposal) { create(:proposal, title: "Medium", cached_votes_up: 5,  tag_list: "Sport") }
      let!(:worst_proposal)  { create(:proposal, title: "Worst",  cached_votes_up: 1,  tag_list: "Sport") }

      scenario "can't be sorted if there's no logged user" do
        visit proposals_path
        expect(page).not_to have_selector("a", text: "recommendations")
      end

      scenario "are shown on index header when account setting is enabled" do
        proposal = create(:proposal, tag_list: "Sport")
        user     = create(:user, followables: [proposal])

        login_as(user)
        visit proposals_path

        expect(page).to have_css(".recommendation", count: 3)
        expect(page).to have_link "Best"
        expect(page).to have_link "Medium"
        expect(page).to have_link "Worst"
        expect(page).to have_link "See more recommendations"
      end

      scenario "should display text when there are no results" do
        proposal = create(:proposal, tag_list: "Distinct_to_sport")
        user     = create(:user, followables: [proposal])

        login_as(user)
        visit proposals_path

        click_link "recommendations"

        expect(page).to have_content "There are not proposals related to your interests"
      end

      scenario "should display text when user has no related interests" do
        user = create(:user)

        login_as(user)
        visit proposals_path

        click_link "recommendations"

        expect(page).to have_content "Follow proposals so we can give you recommendations"
      end

      scenario "can be sorted when there's a logged user" do
        proposal = create(:proposal, tag_list: "Sport")
        user     = create(:user, followables: [proposal])

        login_as(user)
        visit proposals_path

        click_link "recommendations"

        expect(page).to have_selector("a.is-active", text: "recommendations")

        within "#proposals-list" do
          expect(best_proposal.title).to appear_before(medium_proposal.title)
          expect(medium_proposal.title).to appear_before(worst_proposal.title)
        end

        expect(current_url).to include("order=recommendations")
        expect(current_url).to include("page=1")
      end

      scenario "are not shown if account setting is disabled" do
        proposal = create(:proposal, tag_list: "Sport")
        user     = create(:user, recommended_proposals: false, followables: [proposal])

        login_as(user)
        visit proposals_path

        expect(page).not_to have_css(".recommendation", count: 3)
        expect(page).not_to have_link("recommendations")
      end

      scenario "are automatically disabled when dismissed from index", :js do
        proposal = create(:proposal, tag_list: "Sport")
        user     = create(:user, followables: [proposal])

        login_as(user)
        visit proposals_path

        within("#recommendations") do
          expect(page).to have_content("Best")
          expect(page).to have_content("Worst")
          expect(page).to have_content("Medium")
          expect(page).to have_css(".recommendation", count: 3)

          accept_confirm { click_link "Hide recommendations" }
        end

        expect(page).not_to have_link("recommendations")
        expect(page).not_to have_css(".recommendation", count: 3)
        expect(page).to have_content("Recommendations for proposals are now disabled for this account")

        user.reload

        visit account_path

        expect(find("#account_recommended_proposals")).not_to be_checked
        expect(user.recommended_proposals).to be(false)
      end
    end
  end

  describe "Archived proposals" do
    scenario "show on proposals list" do
      archived_proposals = create_archived_proposals

      visit proposals_path
      click_link "Archived proposals"

      within("#proposals-list") do
        archived_proposals.each do |proposal|
          expect(page).to have_content(proposal.title)
        end
      end
    end

    scenario "do not show in other index tabs" do
      archived_proposal = create(:proposal, :archived)

      visit proposals_path

      within("#proposals-list") do
        expect(page).not_to have_content archived_proposal.title
      end

      orders = %w[hot_score confidence_score created_at relevance]
      orders.each do |order|
        visit proposals_path(order: order)

        within("#proposals-list") do
          expect(page).not_to have_content archived_proposal.title
        end
      end
    end

    scenario "do not show support buttons in index" do
      archived_proposals = create_archived_proposals

      visit proposals_path(order: "archival_date")

      within("#proposals-list") do
        archived_proposals.each do |proposal|
          within("#proposal_#{proposal.id}_votes") do
            expect(page).to have_content "This proposal has been archived and can't collect supports"
          end
        end
      end
    end

    scenario "do not show support buttons in show" do
      archived_proposal = create(:proposal, :archived)

      visit proposal_path(archived_proposal)
      expect(page).to have_content "This proposal has been archived and can't collect supports"
    end

    scenario "do not show in featured proposals section" do
      Setting["feature.featured_proposals"] = true
      featured_proposal = create(:proposal, :with_confidence_score, cached_votes_up: 100)
      archived_proposal = create(:proposal, :archived, :with_confidence_score,
                                                        cached_votes_up: 10000)

      visit proposals_path

      within("#featured-proposals") do
        expect(page).to have_content(featured_proposal.title)
        expect(page).not_to have_content(archived_proposal.title)
      end
      within("#proposals-list") do
        expect(page).not_to have_content(featured_proposal.title)
        expect(page).not_to have_content(archived_proposal.title)
      end

      click_link "Archived proposals"

      within("#featured-proposals") do
        expect(page).to have_content(featured_proposal.title)
        expect(page).not_to have_content(archived_proposal.title)
      end
      within("#proposals-list") do
        expect(page).not_to have_content(featured_proposal.title)
        expect(page).to have_content(archived_proposal.title)
      end
    end

    scenario "Order by votes" do
      create(:proposal, :archived, title: "Least voted").update_column(:confidence_score, 10)
      create(:proposal, :archived, title: "Most voted").update_column(:confidence_score, 50)
      create(:proposal, :archived, title: "Some votes").update_column(:confidence_score, 25)

      visit proposals_path
      click_link "Archived proposals"

      within("#proposals-list") do
        expect(all(".proposal")[0].text).to match "Most voted"
        expect(all(".proposal")[1].text).to match "Some votes"
        expect(all(".proposal")[2].text).to match "Least voted"
      end
    end
  end

  context "Selected Proposals" do
    let!(:selected_proposal)     { create(:proposal, :selected) }
    let!(:not_selected_proposal) { create(:proposal) }

    scenario "do not show in index by default" do
      visit proposals_path

      expect(page).to have_selector("#proposals .proposal", count: 1)
      expect(page).to have_content not_selected_proposal.title
      expect(page).not_to have_content selected_proposal.title
    end

    scenario "show in selected proposals list" do
      visit proposals_path
      click_link "View selected proposals"

      expect(page).to have_selector("#proposals .proposal", count: 1)
      expect(page).to have_content selected_proposal.title
      expect(page).not_to have_content not_selected_proposal.title
    end

    scenario "show a selected proposal message in show view" do
      visit proposal_path(selected_proposal)

      within("aside") { expect(page).not_to have_content "SUPPORTS" }
      within("aside") { expect(page).to have_content "Selected proposal" }
    end

    scenario "do not show featured proposal in selected proposals list" do
      Setting["feature.featured_proposals"] = true
      create_featured_proposals

      visit proposals_path

      expect(page).to have_selector("#proposals .proposal-featured")
      expect(page).to have_selector("#featured-proposals")

      click_link "View selected proposals"

      expect(page).not_to have_selector("#proposals .proposal-featured")
      expect(page).not_to have_selector("#featured-proposals")
    end

    scenario "do not show recommented proposal in selected proposals list" do
      user = create(:user)

      create(:proposal, tag_list: "Economy", followers: [user])
      create(:proposal, title: "Recommended", tag_list: "Economy")

      login_as(user)
      visit proposals_path

      expect(page).to have_css(".recommendation", count: 1)
      expect(page).to have_link "Recommended"
      expect(page).to have_link "See more recommendations"

      click_link "View selected proposals"

      expect(page).not_to have_css ".recommendation"
      expect(page).not_to have_link "Recommended"
      expect(page).not_to have_link "See more recommendations"
    end

    scenario "do not show order links in selected proposals list" do
      visit proposals_path

      expect(page).to have_css  "ul.submenu"
      expect(page).to have_link "most active"
      expect(page).to have_link "highest rated"
      expect(page).to have_link "newest"

      click_link "View selected proposals"

      expect(page).not_to have_css  "ul.submenu"
      expect(page).not_to have_link "most active"
      expect(page).not_to have_link "highest rated"
      expect(page).not_to have_link "newest"
    end

    scenario "show archived proposals in selected proposals list" do
      archived_proposal = create(:proposal, :selected, :archived)

      visit proposals_path
      expect(page).not_to have_content archived_proposal.title

      click_link "View selected proposals"
      expect(page).to have_content archived_proposal.title
    end
  end

  context "Search" do
    context "Basic search" do
      scenario "Search by text" do
        proposal1 = create(:proposal, title: "Get Schwifty")
        proposal2 = create(:proposal, title: "Schwifty Hello")
        proposal3 = create(:proposal, title: "Do not show me")

        visit proposals_path

        within(".expanded #search_form") do
          fill_in "search", with: "Schwifty"
          click_button "Search"
        end

        within("#proposals") do
          expect(page).to have_css(".proposal", count: 2)

          expect(page).to have_content(proposal1.title)
          expect(page).to have_content(proposal2.title)
          expect(page).not_to have_content(proposal3.title)
        end
      end

      scenario "Search by proposal code" do
        proposal1 = create(:proposal, title: "Get Schwifty")
        proposal2 = create(:proposal, title: "Schwifty Hello")

        visit proposals_path

        within(".expanded #search_form") do
          fill_in "search", with: proposal1.code
          click_button "Search"
        end

        within("#proposals") do
          expect(page).to have_css(".proposal", count: 1)

          expect(page).to have_content(proposal1.title)
          expect(page).not_to have_content(proposal2.title)
        end
      end

      scenario "Maintain search criteria" do
        visit proposals_path

        within(".expanded #search_form") do
          fill_in "search", with: "Schwifty"
          click_button "Search"
        end

        expect(page).to have_selector("input[name='search'][value='Schwifty']")
      end
    end

    context "Advanced search" do
      scenario "Search by text", :js do
        proposal1 = create(:proposal, title: "Get Schwifty")
        proposal2 = create(:proposal, title: "Schwifty Hello")
        proposal3 = create(:proposal, title: "Do not show me")

        visit proposals_path

        click_link "Advanced search"
        fill_in "Write the text", with: "Schwifty"
        click_button "Filter"

        expect(page).to have_content("There are 2 citizen proposals")

        within("#proposals") do
          expect(page).to have_content(proposal1.title)
          expect(page).to have_content(proposal2.title)
          expect(page).not_to have_content(proposal3.title)
        end
      end

      context "Search by author type" do
        scenario "Public employee", :js do
          ana = create :user, official_level: 1
          john = create :user, official_level: 2

          proposal1 = create(:proposal, author: ana)
          proposal2 = create(:proposal, author: ana)
          proposal3 = create(:proposal, author: john)

          visit proposals_path

          click_link "Advanced search"
          select Setting["official_level_1_name"], from: "advanced_search_official_level"
          click_button "Filter"

          expect(page).to have_content("There are 2 citizen proposals")

          within("#proposals") do
            expect(page).to have_content(proposal1.title)
            expect(page).to have_content(proposal2.title)
            expect(page).not_to have_content(proposal3.title)
          end
        end

        scenario "Municipal Organization", :js do
          ana = create :user, official_level: 2
          john = create :user, official_level: 3

          proposal1 = create(:proposal, author: ana)
          proposal2 = create(:proposal, author: ana)
          proposal3 = create(:proposal, author: john)

          visit proposals_path

          click_link "Advanced search"
          select Setting["official_level_2_name"], from: "advanced_search_official_level"
          click_button "Filter"

          expect(page).to have_content("There are 2 citizen proposals")

          within("#proposals") do
            expect(page).to have_content(proposal1.title)
            expect(page).to have_content(proposal2.title)
            expect(page).not_to have_content(proposal3.title)
          end
        end

        scenario "General director", :js do
          ana = create :user, official_level: 3
          john = create :user, official_level: 4

          proposal1 = create(:proposal, author: ana)
          proposal2 = create(:proposal, author: ana)
          proposal3 = create(:proposal, author: john)

          visit proposals_path

          click_link "Advanced search"
          select Setting["official_level_3_name"], from: "advanced_search_official_level"
          click_button "Filter"

          expect(page).to have_content("There are 2 citizen proposals")

          within("#proposals") do
            expect(page).to have_content(proposal1.title)
            expect(page).to have_content(proposal2.title)
            expect(page).not_to have_content(proposal3.title)
          end
        end

        scenario "City councillor", :js do
          ana = create :user, official_level: 4
          john = create :user, official_level: 5

          proposal1 = create(:proposal, author: ana)
          proposal2 = create(:proposal, author: ana)
          proposal3 = create(:proposal, author: john)

          visit proposals_path

          click_link "Advanced search"
          select Setting["official_level_4_name"], from: "advanced_search_official_level"
          click_button "Filter"

          expect(page).to have_content("There are 2 citizen proposals")

          within("#proposals") do
            expect(page).to have_content(proposal1.title)
            expect(page).to have_content(proposal2.title)
            expect(page).not_to have_content(proposal3.title)
          end
        end

        scenario "Mayoress", :js do
          ana = create :user, official_level: 5
          john = create :user, official_level: 4

          proposal1 = create(:proposal, author: ana)
          proposal2 = create(:proposal, author: ana)
          proposal3 = create(:proposal, author: john)

          visit proposals_path

          click_link "Advanced search"
          select Setting["official_level_5_name"], from: "advanced_search_official_level"
          click_button "Filter"

          expect(page).to have_content("There are 2 citizen proposals")

          within("#proposals") do
            expect(page).to have_content(proposal1.title)
            expect(page).to have_content(proposal2.title)
            expect(page).not_to have_content(proposal3.title)
          end
        end
      end

      context "Search by date" do
        context "Predefined date ranges" do
          scenario "Last day", :js do
            proposal1 = create(:proposal, created_at: 1.minute.ago)
            proposal2 = create(:proposal, created_at: 1.hour.ago)
            proposal3 = create(:proposal, created_at: 2.days.ago)

            visit proposals_path

            click_link "Advanced search"
            select "Last 24 hours", from: "js-advanced-search-date-min"
            click_button "Filter"

            expect(page).to have_content("There are 2 citizen proposals")

            within("#proposals") do
              expect(page).to have_content(proposal1.title)
              expect(page).to have_content(proposal2.title)
              expect(page).not_to have_content(proposal3.title)
            end
          end

          scenario "Last week", :js do
            proposal1 = create(:proposal, created_at: 1.day.ago)
            proposal2 = create(:proposal, created_at: 5.days.ago)
            proposal3 = create(:proposal, created_at: 8.days.ago)

            visit proposals_path

            click_link "Advanced search"
            select "Last week", from: "js-advanced-search-date-min"
            click_button "Filter"

            expect(page).to have_content("There are 2 citizen proposals")

            within("#proposals") do
              expect(page).to have_content(proposal1.title)
              expect(page).to have_content(proposal2.title)
              expect(page).not_to have_content(proposal3.title)
            end
          end

          scenario "Last month", :js do
            proposal1 = create(:proposal, created_at: 10.days.ago)
            proposal2 = create(:proposal, created_at: 20.days.ago)
            proposal3 = create(:proposal, created_at: 33.days.ago)

            visit proposals_path

            click_link "Advanced search"
            select "Last month", from: "js-advanced-search-date-min"
            click_button "Filter"

            expect(page).to have_content("There are 2 citizen proposals")

            within("#proposals") do
              expect(page).to have_content(proposal1.title)
              expect(page).to have_content(proposal2.title)
              expect(page).not_to have_content(proposal3.title)
            end
          end

          scenario "Last year", :js do
            proposal1 = create(:proposal, created_at: 300.days.ago)
            proposal2 = create(:proposal, created_at: 350.days.ago)
            proposal3 = create(:proposal, created_at: 370.days.ago)

            visit proposals_path

            click_link "Advanced search"
            select "Last year", from: "js-advanced-search-date-min"
            click_button "Filter"

            expect(page).to have_content("There are 2 citizen proposals")

            within("#proposals") do
              expect(page).to have_content(proposal1.title)
              expect(page).to have_content(proposal2.title)
              expect(page).not_to have_content(proposal3.title)
            end
          end
        end

        scenario "Search by custom date range", :js do
          proposal1 = create(:proposal, created_at: 2.days.ago)
          proposal2 = create(:proposal, created_at: 3.days.ago)
          proposal3 = create(:proposal, created_at: 9.days.ago)

          visit proposals_path

          click_link "Advanced search"
          select "Customized", from: "js-advanced-search-date-min"
          fill_in "advanced_search_date_min", with: 7.days.ago
          fill_in "advanced_search_date_max", with: 1.day.ago
          click_button "Filter"

          expect(page).to have_content("There are 2 citizen proposals")

          within("#proposals") do
            expect(page).to have_content(proposal1.title)
            expect(page).to have_content(proposal2.title)
            expect(page).not_to have_content(proposal3.title)
          end
        end

        scenario "Search by custom invalid date range", :js do
          proposal1 = create(:proposal, created_at: 2.days.ago)
          proposal2 = create(:proposal, created_at: 3.days.ago)
          proposal3 = create(:proposal, created_at: 9.days.ago)

          visit proposals_path

          click_link "Advanced search"
          select "Customized", from: "js-advanced-search-date-min"
          fill_in "advanced_search_date_min", with: 4000.years.ago
          fill_in "advanced_search_date_max", with: "wrong date"
          click_button "Filter"

          expect(page).to have_content("There are 3 citizen proposals")

          within("#proposals") do
            expect(page).to have_content(proposal1.title)
            expect(page).to have_content(proposal2.title)
            expect(page).to have_content(proposal3.title)
          end
        end

        scenario "Search by multiple filters", :js do
          ana  = create :user, official_level: 1
          john = create :user, official_level: 1

          create(:proposal, title: "Get Schwifty",   author: ana,  created_at: 1.minute.ago)
          create(:proposal, title: "Hello Schwifty", author: john, created_at: 2.days.ago)
          create(:proposal, title: "Save the forest")

          visit proposals_path

          click_link "Advanced search"
          fill_in "Write the text", with: "Schwifty"
          select Setting["official_level_1_name"], from: "advanced_search_official_level"
          select "Last 24 hours", from: "js-advanced-search-date-min"

          click_button "Filter"

          expect(page).to have_content("There is 1 citizen proposal")

          within("#proposals") do
            expect(page).to have_content "Get Schwifty"
          end
        end

        scenario "Maintain advanced search criteria", :js do
          visit proposals_path
          click_link "Advanced search"

          fill_in "Write the text", with: "Schwifty"
          select Setting["official_level_1_name"], from: "advanced_search_official_level"
          select "Last 24 hours", from: "js-advanced-search-date-min"

          click_button "Filter"

          expect(page).to have_content("citizen proposals cannot be found")

          within "#js-advanced-search" do
            expect(page).to have_selector("input[name='search'][value='Schwifty']")
            expect(page).to have_select("advanced_search[official_level]", selected: Setting["official_level_1_name"])
            expect(page).to have_select("advanced_search[date_min]", selected: "Last 24 hours")
          end
        end

        scenario "Maintain custom date search criteria", :js do
          visit proposals_path
          click_link "Advanced search"

          select "Customized", from: "js-advanced-search-date-min"
          fill_in "advanced_search_date_min", with: 7.days.ago.strftime("%d/%m/%Y")
          fill_in "advanced_search_date_max", with: 1.day.ago.strftime("%d/%m/%Y")
          click_button "Filter"

          expect(page).to have_content("citizen proposals cannot be found")

          within "#js-advanced-search" do
            expect(page).to have_select("advanced_search[date_min]", selected: "Customized")
            expect(page).to have_selector("input[name='advanced_search[date_min]'][value*='#{7.days.ago.strftime("%d/%m/%Y")}']")
            expect(page).to have_selector("input[name='advanced_search[date_max]'][value*='#{1.day.ago.strftime("%d/%m/%Y")}']")
          end
        end
      end
    end

    scenario "Order by relevance by default", :js do
      create(:proposal, title: "In summary", summary: "Title content too", cached_votes_up: 10)
      create(:proposal, title: "Title content", summary: "Summary", cached_votes_up: 1)
      create(:proposal, title: "Title here", summary: "Content here", cached_votes_up: 100)

      visit proposals_path
      fill_in "search", with: "Title content"
      click_button "Search"

      expect(page).to have_selector("a.is-active", text: "relevance")

      within("#proposals") do
        expect(all(".proposal")[0].text).to match "Title content"
        expect(all(".proposal")[1].text).to match "Title here"
        expect(all(".proposal")[2].text).to match "In summary"
      end
    end

    scenario "Reorder results maintaing search", :js do
      create(:proposal, title: "Show you got",      cached_votes_up: 10,  created_at: 1.week.ago)
      create(:proposal, title: "Show what you got", cached_votes_up: 1,   created_at: 1.month.ago)
      create(:proposal, title: "Show you got",      cached_votes_up: 100, created_at: Time.current)
      create(:proposal, title: "Do not display",    cached_votes_up: 1,   created_at: 1.week.ago)

      visit proposals_path
      fill_in "search", with: "Show what you got"
      click_button "Search"

      expect(page).to have_content "Search results"

      click_link "newest"

      expect(page).to have_selector("a.is-active", text: "newest")

      within("#proposals") do
        expect(all(".proposal")[0].text).to match "Show you got"
        expect(all(".proposal")[1].text).to match "Show you got"
        expect(all(".proposal")[2].text).to match "Show what you got"
        expect(page).not_to have_content "Do not display"
      end
    end

    scenario "Reorder by recommendations results maintaing search" do
      user = create(:user, recommended_proposals: true)

      create(:proposal, title: "Show you got",      cached_votes_up: 10,  tag_list: "Sport")
      create(:proposal, title: "Show what you got", cached_votes_up: 1,   tag_list: "Sport")
      create(:proposal, title: "Do not display with same tag", cached_votes_up: 100, tag_list: "Sport")
      create(:proposal, title: "Do not display",    cached_votes_up: 1)
      create(:proposal, tag_list: "Sport", followers: [user])

      login_as(user)
      visit proposals_path
      fill_in "search", with: "Show you got"
      click_button "Search"
      click_link "recommendations"
      expect(page).to have_selector("a.is-active", text: "recommendations")

      within("#proposals") do
        expect(all(".proposal")[0].text).to match "Show you got"
        expect(all(".proposal")[1].text).to match "Show what you got"
        expect(page).not_to have_content "Do not display with same tag"
        expect(page).not_to have_content "Do not display"
      end
    end

    scenario "After a search do not show featured proposals" do
      Setting["feature.featured_proposals"] = true
      create_featured_proposals
      create(:proposal, title: "Abcdefghi")

      visit proposals_path
      within(".expanded #search_form") do
        fill_in "search", with: "Abcdefghi"
        click_button "Search"
      end

      expect(page).not_to have_selector("#proposals .proposal-featured")
      expect(page).not_to have_selector("#featured-proposals")
    end
  end

  scenario "Conflictive" do
    good_proposal = create(:proposal)
    conflictive_proposal = create(:proposal, :conflictive)

    visit proposal_path(conflictive_proposal)
    expect(page).to have_content "This proposal has been flagged as inappropriate by several users."

    visit proposal_path(good_proposal)
    expect(page).not_to have_content "This proposal has been flagged as inappropriate by several users."
  end

  it_behaves_like "followable", "proposal", "proposal_path", { "id": "id" }

  it_behaves_like "imageable", "proposal", "proposal_path", { "id": "id" }

  it_behaves_like "nested imageable",
                  "proposal",
                  "new_proposal_path",
                  {},
                  "imageable_fill_new_valid_proposal",
                  "Create proposal",
                  "Proposal created successfully"

  it_behaves_like "nested imageable",
                  "proposal",
                  "edit_proposal_path",
                  { "id": "id" },
                  nil,
                  "Save changes",
                  "Proposal updated successfully"

  it_behaves_like "documentable", "proposal", "proposal_path", { "id": "id" }

  it_behaves_like "nested documentable",
                  "user",
                  "proposal",
                  "new_proposal_path",
                  {},
                  "documentable_fill_new_valid_proposal",
                  "Create proposal",
                  "Proposal created successfully"

  it_behaves_like "nested documentable",
                  "user",
                  "proposal",
                  "edit_proposal_path",
                  { "id": "id" },
                  nil,
                  "Save changes",
                  "Proposal updated successfully"

  it_behaves_like "mappable",
                  "proposal",
                  "proposal",
                  "new_proposal_path",
                  "edit_proposal_path",
                  "proposal_path",
                  {}

  scenario "Erased author" do
    Setting["feature.featured_proposals"] = true
    user = create(:user)
    proposal = create(:proposal, author: user)
    user.erase

    visit proposals_path
    expect(page).to have_content("User deleted")

    visit proposal_path(proposal)
    expect(page).to have_content("User deleted")

    create_featured_proposals

    visit proposals_path
    expect(page).to have_content("User deleted")
  end

  context "Filter" do
    context "By geozone" do
      let(:california) { Geozone.create(name: "California") }
      let(:new_york)   { Geozone.create(name: "New York") }

      before do
        create(:proposal, geozone: california, title: "Bigger sequoias")
        create(:proposal, geozone: california, title: "Green beach")
        create(:proposal, geozone: new_york, title: "Sully monument")
      end

      scenario "From map" do
        visit proposals_path

        click_link "map"
        within("#html_map") do
          url = find("area[title='California']")[:href]
          visit url
        end

        within("#proposals") do
          expect(page).to have_css(".proposal", count: 2)
          expect(page).to have_content("Bigger sequoias")
          expect(page).to have_content("Green beach")
          expect(page).not_to have_content("Sully monument")
        end
      end

      scenario "From geozone list" do
        visit proposals_path

        click_link "map"
        within("#geozones") do
          click_link "California"
        end
        within("#proposals") do
          expect(page).to have_css(".proposal", count: 2)
          expect(page).to have_content("Bigger sequoias")
          expect(page).to have_content("Green beach")
          expect(page).not_to have_content("Sully monument")
        end
      end

      scenario "From proposal" do
        proposal = create(:proposal, geozone: california, title: "Surf college")

        visit proposal_path(proposal)

        within("#geozone") do
          click_link "California"
        end

        within("#proposals") do
          expect(page).to have_css(".proposal", count: 3)
          expect(page).to have_content("Surf college")
          expect(page).to have_content("Bigger sequoias")
          expect(page).to have_content("Green beach")
          expect(page).not_to have_content("Sully monument")
        end
      end
    end
  end

  context "Suggesting proposals" do
    scenario "Show up to 5 suggestions", :js do
      create(:proposal, title: "First proposal, has search term")
      create(:proposal, title: "Second title")
      create(:proposal, title: "Third proposal, has search term")
      create(:proposal, title: "Fourth proposal, has search term")
      create(:proposal, title: "Fifth proposal, has search term")
      create(:proposal, title: "Sixth proposal, has search term")
      create(:proposal, title: "Seventh proposal, has search term")

      login_as(create(:user))
      visit new_proposal_path
      fill_in "Proposal title", with: "search"
      check "proposal_terms_of_service"

      within("div.js-suggest") do
        expect(page).to have_content "You are seeing 5 of 6 proposals containing the term 'search'"
      end
    end

    scenario "No found suggestions", :js do
      create(:proposal, title: "First proposal").update_column(:confidence_score, 10)
      create(:proposal, title: "Second proposal").update_column(:confidence_score, 8)

      login_as(create(:user))
      visit new_proposal_path
      fill_in "Proposal title", with: "debate"
      check "proposal_terms_of_service"

      within("div.js-suggest") do
        expect(page).not_to have_content "You are seeing"
      end
    end
  end

  context "Summary" do
    scenario "Displays proposals grouped by category" do
      create(:tag, :category, name: "Culture")
      create(:tag, :category, name: "Social Services")

      3.times { create(:proposal, tag_list: "Culture") }
      3.times { create(:proposal, tag_list: "Social Services") }

      create(:proposal, tag_list: "Random")

      visit proposals_path
      click_link "The most supported proposals by category"

      within("#culture") do
        expect(page).to have_content("Culture")
        expect(page).to have_css(".proposal", count: 3)
      end

      within("#social-services") do
        expect(page).to have_content("Social Services")
        expect(page).to have_css(".proposal", count: 3)
      end
    end

    scenario "Displays proposals grouped by district" do
      california = create(:geozone, name: "California")
      new_york   = create(:geozone, name: "New York")

      3.times { create(:proposal, geozone: california) }
      3.times { create(:proposal, geozone: new_york) }

      visit proposals_path
      click_link "The most supported proposals by category"

      within("#california") do
        expect(page).to have_content("California")
        expect(page).to have_css(".proposal", count: 3)
      end

      within("#new-york") do
        expect(page).to have_content("New York")
        expect(page).to have_css(".proposal", count: 3)
      end
    end

    scenario "Displays a maximum of 3 proposals per category" do
      create(:tag, :category, name: "culture")
      4.times { create(:proposal, tag_list: "culture") }

      visit summary_proposals_path

      expect(page).to have_css(".proposal", count: 3)
    end

    scenario "Orders proposals by votes" do
      create(:tag, :category, name: "culture")
      best_proposal = create(:proposal, title: "Best", tag_list: "culture")
      best_proposal.update_column(:confidence_score, 10)
      worst_proposal = create(:proposal, title: "Worst", tag_list: "culture")
      worst_proposal.update_column(:confidence_score, 2)
      medium_proposal = create(:proposal, title: "Medium", tag_list: "culture")
      medium_proposal.update_column(:confidence_score, 5)

      visit summary_proposals_path

      expect(best_proposal.title).to appear_before(medium_proposal.title)
      expect(medium_proposal.title).to appear_before(worst_proposal.title)
    end

    scenario "Displays proposals from last week" do
      create(:tag, :category, name: "culture")
      proposal1 = create(:proposal, tag_list: "culture", created_at: 1.day.ago)
      proposal2 = create(:proposal, tag_list: "culture", created_at: 5.days.ago)
      proposal3 = create(:proposal, tag_list: "culture", created_at: 8.days.ago)

      visit summary_proposals_path

      within("#proposals") do
        expect(page).to have_css(".proposal", count: 2)

        expect(page).to have_content(proposal1.title)
        expect(page).to have_content(proposal2.title)
        expect(page).not_to have_content(proposal3.title)
      end
    end
  end
end

describe "Successful proposals" do
  scenario "Successful proposals do not show support buttons in index" do
    successful_proposals = create_successful_proposals

    visit proposals_path

    successful_proposals.each do |proposal|
      within("#proposal_#{proposal.id}_votes") do
        expect(page).not_to have_link "Support"
        expect(page).to have_content "100% / 100%"
      end
    end
  end

  scenario "Successful proposals do not show support buttons in show" do
    successful_proposals = create_successful_proposals

    successful_proposals.each do |proposal|
      visit proposal_path(proposal)
      within("#proposal_#{proposal.id}_votes") do
        expect(page).not_to have_link "Support"
        expect(page).to have_content "100% / 100%"
      end
    end
  end

  scenario "Successful proposals do not show create question button in index" do
    successful_proposals = create_successful_proposals
    admin = create(:administrator)

    login_as(admin.user)

    visit proposals_path

    successful_proposals.each do |proposal|
      within("#proposal_#{proposal.id}_votes") do
        expect(page).not_to have_link "Create question"
      end
    end
  end

  scenario "Successful proposals do not show create question button in show" do
    successful_proposals = create_successful_proposals
    admin = create(:administrator)

    login_as(admin.user)

    successful_proposals.each do |proposal|
      visit proposal_path(proposal)
      within("#proposal_#{proposal.id}_votes") do
        expect(page).not_to have_link "Create question"
      end
    end
  end

  context "Skip user verification" do
    before do
      Setting["feature.user.skip_verification"] = "true"
    end

    scenario "Create" do
      author = create(:user)
      login_as(author)

      visit proposals_path

      within("aside") do
        click_link "Create a proposal"
      end

      expect(page).to have_current_path(new_proposal_path)

      fill_in "Proposal title", with: "Help refugees"
      fill_in "Proposal summary", with: "In summary what we want is..."
      fill_in "Proposal text", with: "This is very important because..."
      fill_in "proposal_video_url", with: "https://www.youtube.com/watch?v=yPQfcG-eimk"
      fill_in "proposal_tag_list", with: "Refugees, Solidarity"
      check "proposal_terms_of_service"

      click_button "Create proposal"

      expect(page).to have_content "Proposal created successfully."
    end
  end
end