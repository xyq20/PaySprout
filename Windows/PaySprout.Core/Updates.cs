using System.Diagnostics;
using System.IO.Compression;
using System.Net;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;
namespace PaySprout;

public static class UpdatePolicy
{
    public static Version? ParseVersion(string text) {
        if (!Regex.IsMatch(text,@"^v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")) return null;
        return Version.TryParse(text.TrimStart('v'),out var version) ? version : null;
    }
    public static bool IsNewer(string current, string candidate) => ParseVersion(current) is {} old && ParseVersion(candidate) is {} next && next > old;
    public static bool SafeArchivePath(string path) {
        if (string.IsNullOrEmpty(path) || path.StartsWith('/') || path.Contains('\\') || path.Contains(':') || path.Contains('\0')) return false;
        var clean=path.EndsWith('/') ? path[..^1] : path;
        return clean.Split('/').All(part => part.Length > 0 && part != "." && part != "..");
    }
    public static UpdateRelease? ParseRelease(string json,string current) {
        using var doc=JsonDocument.Parse(json); var release=doc.RootElement;
        if (release.GetProperty("draft").GetBoolean() || release.GetProperty("prerelease").GetBoolean()) return null;
        var tag=release.GetProperty("tag_name").GetString() ?? "";
        var version=ParseVersion(tag);
        if (version == null || tag != "v"+version) throw new InvalidDataException("发布版本号格式无效。");
        if (!IsNewer(current,version.ToString())) return null;
        var name=$"PaySprout-{version}-Windows-x64.zip";
        var matches=release.GetProperty("assets").EnumerateArray().Where(a => a.GetProperty("name").GetString()==name).ToArray();
        if(matches.Length!=1) throw new InvalidDataException("此版本暂未提供 Windows 更新包，请稍后重试。");
        var asset=matches[0]; var id=asset.GetProperty("id").GetInt64(); var size=asset.GetProperty("size").GetInt64();
        var digest=asset.TryGetProperty("digest",out var value) ? value.GetString() ?? "" : "";
        var url=$"https://api.github.com/repos/xyq20/PaySprout/releases/assets/{id}";
        if(id<=0 || size<=0 || size>512L*1024*1024 || !Regex.IsMatch(digest,@"^sha256:[0-9a-f]{64}$") || asset.GetProperty("url").GetString()!=url) throw new InvalidDataException("更新包缺少有效校验信息，已停止更新。");
        var notes=release.TryGetProperty("body",out var body) ? body.GetString() ?? "" : "";
        return new(version.ToString(),name,new Uri(url),digest[7..],size,notes[..Math.Min(6000,notes.Length)]);
    }
}

public record UpdateRelease(string Version,string Name,Uri DownloadUrl,string Sha256,long Size,string Notes)
{
    public Uri NotesUrl => new($"https://github.com/xyq20/PaySprout/releases/tag/v{Version}");
}

public sealed class UpdateClient : IDisposable
{
    private readonly HttpClient http;
    public UpdateClient(HttpClient? client=null) { http=client ?? new HttpClient { Timeout=TimeSpan.FromMinutes(30) }; }
    private static HttpRequestMessage Request(Uri url,bool binary=false) {
        var request=new HttpRequestMessage(HttpMethod.Get,url);
        request.Headers.UserAgent.ParseAdd("PaySprout-Updater/1.0");
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue(binary ? "application/octet-stream" : "application/vnd.github+json"));
        request.Headers.Add("X-GitHub-Api-Version","2022-11-28"); return request;
    }
    public async Task<UpdateRelease?> CheckAsync(string current,CancellationToken token=default) {
        using var request=Request(new Uri("https://api.github.com/repos/xyq20/PaySprout/releases/latest"));
        using var response=await http.SendAsync(request,token);
        if(response.StatusCode==HttpStatusCode.NotFound) return null;
        response.EnsureSuccessStatusCode();
        return UpdatePolicy.ParseRelease(await response.Content.ReadAsStringAsync(token),current);
    }
    public static async Task VerifyAsync(string file,UpdateRelease update,CancellationToken token=default) {
        await using var stream=File.OpenRead(file);
        if(stream.Length!=update.Size || Convert.ToHexString(await SHA256.HashDataAsync(stream,token)).ToLowerInvariant()!=update.Sha256) throw new InvalidDataException("下载文件不完整或校验失败，请重新下载。");
    }
    public async Task DownloadAsync(UpdateRelease update,string file,IProgress<double>? progress=null,CancellationToken token=default) {
        using var request=Request(update.DownloadUrl,true);
        using var response=await http.SendAsync(request,HttpCompletionOption.ResponseHeadersRead,token);
        response.EnsureSuccessStatusCode();
        if (response.RequestMessage?.RequestUri?.Scheme != "https") throw new InvalidDataException("更新下载地址无效。");
        if(response.Content.Headers.ContentLength is long length && length!=update.Size) throw new InvalidDataException("更新包大小不匹配。");
        bool created=false;
        try {
            await using(var input=await response.Content.ReadAsStreamAsync(token))
            await using(var output=new FileStream(file,FileMode.CreateNew,FileAccess.Write,FileShare.None,81920,true)) {
                created=true;
                var buffer=new byte[81920]; long total=0; int read;
                while((read=await input.ReadAsync(buffer,token))>0) {
                    total+=read; if(total>update.Size) throw new InvalidDataException("更新包超过预期大小。");
                    await output.WriteAsync(buffer.AsMemory(0,read),token); progress?.Report((double)total/update.Size);
                }
            }
            await VerifyAsync(file,update,token);
        } catch { if(created) File.Delete(file); throw; }
    }
    public static string ExtractExe(string zip,string workspace) {
        using var archive=ZipFile.OpenRead(zip);
        if(archive.Entries.Any(e => !UpdatePolicy.SafeArchivePath(e.FullName) || ((e.ExternalAttributes>>16)&0xf000)==0xa000) || archive.Entries.Sum(e=>e.Length)>512L*1024*1024) throw new InvalidDataException("更新包目录结构不安全。");
        var files=archive.Entries.Where(e=>e.FullName.Equals("PaySprout.exe",StringComparison.OrdinalIgnoreCase)).ToArray();
        if(files.Length!=1 || files[0].Length<2) throw new InvalidDataException("更新包缺少应用程序。");
        var destination=Path.Combine(workspace,"payload.exe"); files[0].ExtractToFile(destination,false); return destination;
    }
    public void Dispose() => http.Dispose();
}
