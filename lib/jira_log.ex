defmodule JiraLog do

  @doc """
  List the properties (display_name, email_address, avatar) for the user
  """
  def myself, do: myself(user())
  def myself(%JiraUser{server: server, user: user, pass: pass}) do
    url = "#{server}/rest/api/2/myself"
    case HTTPoison.get url, headers(user, pass) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        body
        |> Poison.decode!
        |> extract_user
      _ -> nil
    end
  end

  defp extract_user(response) do
    %JiraUser{
      display_name: response["displayName"],
      email_address: response["emailAddress"],
      avatar: response["avatarUrls"]["48x48"]
    }
  end

  @doc """
  Print the total amount of worklog for the current user.
  """
  def times do
    list  = list_logs()
    list
    |> Stream.flat_map(&(&1.times)) 
    |> Stream.map(&(&1.seconds)) 
    |> Enum.reduce(0, &+/2)
    |> format_seconds
    |> IO.puts 

    list
    |> Enum.each(&IO.inspect/1)
  end

  @doc """
  List all the worklog items on the current date for the current user
  """
  def list_logs, do: list_logs(today_user_filter(), user())
  @doc """
  List all the worklog items using a filter.
  
  ## Example:
  `JiraLog.list_logs(
    %WorklogFilter{user: "myuser", date_from: ~D[2017-07-01], date_to: ~D[2017-07-30]},
    %JiraUser{server: "http://myserver.com", user: "user", pass: "xyz"}
  )`
  """
  def list_logs(%WorklogFilter{} = filter, %JiraUser{} = user) do
    query(user, filter)
    |> Enum.map(&(worklogs_for_issue(user, &1, filter)))
  end

  defp user do
    domain = Application.get_env(:jira_log, :server)
    user = Application.get_env(:jira_log, :user)
    pass = Application.get_env(:jira_log, :pass)
    %JiraUser{server: domain, user: user, pass: pass}
  end

  defp today_user_filter do
    user = Application.get_env(:jira_log, :user)
    {erl_date, _} = :calendar.local_time()
    date = Date.from_erl!(erl_date)
    %WorklogFilter{user: user, date_from: date, date_to: date}
  end

  defp headers(user, pass) do
    token = Base.encode64("#{user}:#{pass}")
    ["Authorization": "Basic #{token}"]
  end

  defp build_jql(%WorklogFilter{user: user, date_from: df, date_to: dt}) do
    date1 = Date.to_iso8601(df)
    date2 = Date.to_iso8601(dt)
    user = format_user(user)
    cond do
      Date.compare(df, dt) == :eq ->
        ~s{worklogAuthor = #{user} and worklogDate = #{date1}}
      true -> 
        ~s{worklogAuthor = #{user} and worklogDate >= #{date1} and worklogDate <= #{date2}}
    end
  end

  defp format_user(nil), do: "currentUser()"
  defp format_user(""), do: "currentUser()"
  defp format_user(user) do
    ~s("#{user}")
  end

  @doc """
  Retrieves the issues modified on the current date for the current user
  The issues are returned as a list of tuples (issue_id, description)
  """
  def query(
    %JiraUser{server: server, user: user, pass: pass}, 
    %WorklogFilter{} = filter) do
    jql = build_jql(filter)
    fields = "key,summary"
    search_url = "#{server}/rest/api/2/search?jql=#{jql}&fields=#{fields}&maxResults=10000"
    case HTTPoison.get! URI.encode(search_url), headers(user, pass) do 
      %HTTPoison.Response{status_code: 200, body: body} ->
      body
      |> Poison.decode!
      |> list_of_issues
    end
  end

  def format_seconds(seconds) do
    h = div(seconds, 3600)
    "#{h}h #{div(seconds - h * 3600, 60)}m"
  end

  defp list_of_issues(response) do
    response["issues"]
    |> Enum.map(fn item -> {item["key"], item["fields"]["summary"]} end)
  end

  defp worklogs_for_issue(%JiraUser{server: server, user: user, pass: pass},
                          {issue_id, description},
    %WorklogFilter{} = filter
  ) do
    url = "#{server}/rest/api/2/issue/#{issue_id}/worklog"
    %HTTPoison.Response{status_code: 200, body: body} = HTTPoison.get! url, headers(user, pass)
    times = 
      body
      |> Poison.decode!
      |> filter(filter)
      |> extract_worklog
    %{issue: issue_id, description: description, times: times}
  end

  defp filter(response, %WorklogFilter{}=filter) do
    response["worklogs"]
    |> filter_user(filter.user)
    |> filter_date(filter.date_from, filter.date_to)
  end

  defp filter_user(worklogs, ""), do: worklogs
  defp filter_user(worklogs, user) do
    worklogs
    |> Stream.filter(fn item ->
      item["author"]["emailAddress"] == user or 
      item["author"]["key"] == user
    end)
  end

  defp filter_date(worklogs, date1, date2) do
    worklogs
    |> Stream.filter(fn item -> 
      started = item["started"]
      |> String.slice(0..9)
      |> Date.from_iso8601!
      started >= date1 && started <= date2
    end)
  end

  defp extract_worklog(worklogs) do
    worklogs
    |> Enum.map(fn item -> 
      %JiraWorklog{
        user: item["author"]["emailAddress"],
        seconds: item["timeSpentSeconds"],
        created: item["created"],
        started: item["started"],
        time_spent: item["timeSpent"],
        comment: item["comment"]
      }
    end) 
  end

end
