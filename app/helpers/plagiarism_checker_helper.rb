
class PlagiarismCheckerHelper
  require 'simicheck_webservice'
  require 'submission_content_fetcher'

  # PlagiarismCheckerHelper acts as the integration point between all services and models
  # related to PlagiarismChecker

  def self.run(assignment_id)
    assignment = Assignment.find(assignment_id)
    teams = Team.where(parent_id: assignment_id)

    puts "Started comparison for assignment #{assignment_id}"

    self.send_notification_email("task started")

    code_assignment_submission_id = self.create_new_assignment_submission(assignment.name + " (Code)")
    doc_assignment_submission_id  = self.create_new_assignment_submission(assignment.name + " (Doc)")

    puts "Created code submission #{code_assignment_submission_id}, and doc submission #{doc_assignment_submission_id}"

    for team in teams
      puts "Getting submission links for team #{team}"
      
      for url in team.hyperlinks # in assignment_team model
        fetcher = SubmissionContentFetcher.CodeFactory(url)
        id = code_assignment_submission_id

        if not fetcher
          fetcher = SubmissionContentFetcher.DocFactory(url)
          id = doc_assignment_submission_id
        end

        puts "Created fetcher for URL: #{url}"

        if fetcher
          content = fetcher.fetch_content
          if content.length > 0
            self.upload_file(id, team.id)
            puts "File uploaded for team #{team.id}"
          else
            msg = "no content found for submission URL: " + url
            puts msg
            self.send_notification_email(msg)
          end

        else
          self.send_notification_email("invalid submission URL: " + url)
        end
      end # each submission per team
    end # each team

    # TODO: Bradford enter callback URL here
    # Start comparison on code submission
    callback_url = request.protocol + request.host + "/" + code_assignment_submission_id
    self.start_plagiarism_checker(code_assignment_submission_id, callback_url)
    # Start comparison on doc submission
    callback_url = request.protocol + request.host + "/" + doc_assignment_submission_id
    self.start_plagiarism_checker(doc_assignment_submission_id, callback_url)
    
    self.send_notification_email("submission comparison started")
  end

  def self.send_notification_email(type)
  end

  # Create a new PlagiarismCheckerAssignmentSubmission
  def self.create_new_assignment_submission(submission_name = '')
    # Start by creating a new assignment submission
    response = SimiCheckWebService.new_comparison(submission_name)
    json_response = JSON.parse(response.body)
    as_name = json_response["name"]
    as_id = json_response["id"]
    assignment_submission = PlagiarismCheckerAssignmentSubmission.new(name: as_name, simicheck_id: as_id)
    assignment_submission.save!
    as_id
  end

  # Upload file (do we have text at this point?)
  def self.upload_file(assignment_submission_simicheck_id, team_id)
    # Setup file number (for unique files)
    filenumber = 1
    # Call method to parse text
    parsed_text = # TODO: David's parser
      # Set up filename structure: "teamID_000N.txt"
      filename = team_id + "_%04d.txt" % filenumber
    # Set up full filepath (in tmp dir)
    filepath = "tmp/" + filename
    # Create new file using parsed text
    File.open(filename, "w") { |file| file.write(parsed_text) }
    # Upload file to simicheck
    response = SimiCheckWebService.upload_file(assignment_submission_simicheck_id, filepath)
  end

  def self.start_plagiarism_checker(assignment_submission_simicheck_id, callback_url)
    # callback_url = server.com/plagiarism_checker_results/<assignment_submission_simicheck_id>
    response = SimiCheckWebService.post_similarity_nxn(assignment_submission_simicheck_id, callback_url)
  end

  def self.store_results(assignment_submission_simicheck_id, threshold)
    response = SimiCheckWebService.get_similarity_nxn(assignment_submission_simicheck_id)
    json_response = JSON.parse(response.body)
    json_response["similarities"].each do |similarity|
      if similarity["similarity"] >= threshold
        # Similarity Percent
        percent_similar = similarity["similarity"].to_s
        # File 1 name
        f1_name = similarity["fn1"]
        # File 2 name
        f2_name = similarity["fn2"]
        # File 1 ID
        f1_id = similarity["fid1"]
        # File 2 ID
        f2_id = similarity["fid2"]
        # Team ID is embedded in the file name
        # Team 1 ID
        t1_id = f1_name.split("_").first
        # Team 2 ID
        t2_id = f2_name.split("_").first
        # Get similarity display link
        get_sim_link_response = SimiCheckWebService.visualize_comparison(assignment_submission_simicheck_id, f1_id, f2_id)
        sim_link = 'https://www.simicheck.com' + get_sim_link_response.body

        comparison = PlagiarismCheckerComparison.new(similarity_link: sim_link, similarity_percentage: percent_similar, file1_name: f1_name, file1_id: f1_id, file1_team: t1_id, file2_name: f2_name, file2_id: f2_id, file2_team: t2_id)
        comparison.save!
      end
    end
  end

end
