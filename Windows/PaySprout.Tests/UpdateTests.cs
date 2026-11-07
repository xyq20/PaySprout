using PaySprout;
using System.IO.Compression;
using System.Net;
using System.Text.Json.Nodes;

internal static class UpdateTests
{
    public static async Task RunAsync(Action<bool,string> check)
    {
        var fixture=File.ReadAllText("Tests/UpdateRelease.json");
        var release=UpdatePolicy.ParseRelease(fixture,"0.1.1")!;
        check(release.Version=="0.2.0" && release.Name.EndsWith("Windows-x64.zip"),"Windows package selection");
        check(UpdatePolicy.ParseRelease(fixture,"0.2.0")==null && UpdatePolicy.ParseRelease(fixture,"1.0.0")==null,"No same-version or downgrade");
        foreach(var key in new[]{"draft","prerelease"}) { var json=JsonNode.Parse(fixture)!; json[key]=true; check(UpdatePolicy.ParseRelease(json.ToJsonString(),"0.1.1")==null,"Skip "+key); }
        foreach(var key in new[]{"digest","url","size","name"}) {
            var json=JsonNode.Parse(fixture)!; var asset=json["assets"]![1]!;
            if(key=="size") asset[key]=0; else asset[key]="bad";
            try { UpdatePolicy.ParseRelease(json.ToJsonString(),"0.1.1"); check(false,"Reject invalid "+key); } catch(InvalidDataException) { check(true,"Rejected "+key); }
        }
        var directory=Path.Combine(Path.GetTempPath(),"PaySprout-tests-"+Guid.NewGuid()); Directory.CreateDirectory(directory);
        try {
            var bytes=System.Text.Encoding.UTF8.GetBytes("verified update fixture");
            var file=Path.Combine(directory,"download.zip");
            using(var client=new UpdateClient(new HttpClient(new FakeHandler(request=> {
                check(request.RequestUri==release.DownloadUrl && request.Headers.Accept.Any(v=>v.MediaType=="application/octet-stream"),"Public GitHub asset request");
                return new HttpResponseMessage(HttpStatusCode.OK) { Content=new ByteArrayContent(bytes),RequestMessage=request };
            })))) { await client.DownloadAsync(release,file); check(File.ReadAllBytes(file).SequenceEqual(bytes),"Download correct bytes"); }
            File.Delete(file);
            var tampered=System.Text.Encoding.UTF8.GetBytes("modified update fixture");
            using(var client=new UpdateClient(new HttpClient(new FakeHandler(request=>new(HttpStatusCode.OK) { Content=new ByteArrayContent(tampered),RequestMessage=request })))) {
                try { await client.DownloadAsync(release,file); check(false,"Reject damaged download"); } catch(InvalidDataException) { check(!File.Exists(file),"Damaged download removed"); }
            }
            using(var client=new UpdateClient(new HttpClient(new FakeHandler(request=>new(HttpStatusCode.ServiceUnavailable) { RequestMessage=request })))) {
                try { await client.DownloadAsync(release,file); check(false,"Reject HTTP failure"); } catch(HttpRequestException) { check(!File.Exists(file),"HTTP failure keeps no partial package"); }
            }
            using(var cancelled=new CancellationTokenSource()) {
                cancelled.Cancel(); using var client=new UpdateClient(new HttpClient(new FakeHandler(_=>new(HttpStatusCode.OK) { Content=new ByteArrayContent(bytes) })));
                try { await client.DownloadAsync(release,file,token:cancelled.Token); check(false,"Cancel download"); } catch(OperationCanceledException) { check(!File.Exists(file),"Cancellation keeps no partial package"); }
            }
            foreach(var badPath in new[]{"../escaped.exe","/absolute.exe","nested\\..\\escape.exe"}) {
                var zip=Path.Combine(directory,Guid.NewGuid()+".zip");
                using(var archive=ZipFile.Open(zip,ZipArchiveMode.Create)) { using var writer=new StreamWriter(archive.CreateEntry(badPath).Open()); writer.Write("bad"); }
                try { UpdateClient.ExtractExe(zip,directory); check(false,"Reject Zip Slip"); } catch(InvalidDataException) { check(true,"Rejected unsafe ZIP"); }
            }
            var validZip=Path.Combine(directory,"valid.zip");
            using(var archive=ZipFile.Open(validZip,ZipArchiveMode.Create)) { using var writer=new StreamWriter(archive.CreateEntry("PaySprout.exe").Open()); writer.Write("MZ fixture"); }
            check(File.ReadAllText(UpdateClient.ExtractExe(validZip,directory))=="MZ fixture","Extract intended payload only");
        } finally { Directory.Delete(directory,true); }
    }
    private sealed class FakeHandler(Func<HttpRequestMessage,HttpResponseMessage> reply) : HttpMessageHandler {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken token) { token.ThrowIfCancellationRequested(); return Task.FromResult(reply(request)); }
    }
}
