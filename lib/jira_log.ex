defmodule JiraLog do

  @domain Application.get_env(:jira_log, :server)
  @user Application.get_env(:jira_log, :user)
  @pass Application.get_env(:jira_log, :pass)

  def query do
    query = "assignee = currentUser()"
    fields = "key,summary"
    search_url = "#{@domain}/rest/api/2/search?jql=#{query}&fields=#{fields}&maxResults=10000"
    case HTTPoison.get! URI.encode(search_url), headers do 
      %HTTPoison.Response{status_code: 200, body: body} ->
      body
      |> Poison.decode!
      |> list_of_issues
    end
  end

  def times do
    query
    |> Enum.map(&time_for_issue/1)
  end

  defp list_of_issues(response) do
    response["issues"]
    |> Enum.map(fn item -> {item["key"], item["fields"]["summary"]} end)
  end

  defp time_for_issue({id, _} = issue) do
    url = "#{@domain}/rest/api/2/issue/#{id}/worklog"
    %HTTPoison.Response{status_code: 200, body: body} = HTTPoison.get! url, headers
    times = 
      body
      |> Poison.decode!
      |> extract_time
    %{issue: issue, times: times}
  end

  defp headers do
    token = Base.encode64("#{@user}:#{@pass}")
    ["Authorization": "Basic #{token}"]
  end

  defp extract_time(response) do
    response["worklogs"]
    |> Enum.map(fn item -> {item["author"]["emailAddress"], item["timeSpentSeconds"]} end) 
  end

end
