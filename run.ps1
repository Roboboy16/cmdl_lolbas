param(
	[int]$Port = 8000, # FileServer Port
	[Parameter(Mandatory=$true)][string]$Filename, # Filename to be downloaded
	[Parameter(Mandatory=$true)][string]$Dir, # Dir in which file would be downloaded
	[string]$ServerPath = "$Env:UserName\Documents\" # Dir from which files would be served
)

function RunServer($Port, $ServerPath) {
	cd $ServerPath;
	$httpsrvlsnr = New-Object System.Net.HttpListener;
	$httpsrvlsnr.Prefixes.Add("http://localhost:$Port/");
	$httpsrvlsnr.Start();
	$webroot = New-PSDrive -Name webroot -PSProvider FileSystem -Root $PWD.Path
	[byte[]]$buffer = $null	

	while ($httpsrvlsnr.IsListening) {
	    try {
	        $ctx = $httpsrvlsnr.GetContext();
	        
	        if ($ctx.Request.RawUrl -eq "/") {
	            $buffer = [System.Text.Encoding]::UTF8.GetBytes("<html><pre>$(Get-ChildItem -Path $PWD.Path -Force | Out-String)</pre></html>");
	            $ctx.Response.ContentLength64 = $buffer.Length;
	            $ctx.Response.OutputStream.WriteAsync($buffer, 0, $buffer.Length)
	        }
	        elseif ($ctx.Request.RawUrl -eq "/stop"){
	            $httpsrvlsnr.Stop();
	            Remove-PSDrive -Name webroot -PSProvider FileSystem;
	        }
	        elseif ($ctx.Request.RawUrl -match "\/[A-Za-z0-9-\s.)(\[\]]") {
	            if ([System.IO.File]::Exists((Join-Path -Path $PWD.Path -ChildPath $ctx.Request.RawUrl.Trim("/\")))) {
	                $buffer = [System.Text.Encoding]::UTF8.GetBytes((Get-Content -Path (Join-Path -Path $PWD.Path -ChildPath $ctx.Request.RawUrl.Trim("/\"))));
	                $ctx.Response.ContentLength64 = $buffer.Length;
	                $ctx.Response.OutputStream.WriteAsync($buffer, 0, $buffer.Length)
	            } 
	        }	

	    }
	    catch [System.Net.HttpListenerException] {
	        Write-Host ($_);
	    }
	}
}


$Settings = @"
[Connection Manager] 
CMSFile=settings.txt 
ServiceName=WindowsUpdate 
TunnelFile=settings.txt 	
[Settings] 
UpdateUrl=http://localhost:$Port/$Filename
"@

New-Item -Path $Dir -ItemType Directory | Out-Null;
$Acl = Get-Acl $Dir;
$Identity = $Env:Username;
$Permissions = "DeleteSubdirectoriesAndFiles,Delete";
$Inherit = "ContainerInherit,ObjectInherit";
$AR = New-Object System.Security.AccessControl.FileSystemAccessRule $Identity, $Permissions, $Inherit, "None", "Deny";
$Acl.AddAccessRule($AR);
Set-Acl -Path $Dir -AclObject $Acl | Out-Null;
$Settings | Out-File -FilePath "$Dir\settings.txt";
$Job = Start-Job -ScriptBlock ${Function:RunServer} -ArgumentList $Port, $ServerPath;
$OldTmp = $Env:tmp.Clone();
$Env:tmp = $Dir;
cmdl32 /vpn /lan $Dir\settings.txt | Out-Null;
$Acl.RemoveAccessRule($AR) | Out-Null;
Set-Acl -Path $Dir -AclObject $Acl;
Get-ChildItem -Path $Dir -Filter "*.tmp" | Rename-Item -NewName $Filename;

#Cleaning
Get-ChildItem -Path $Dir -Exclude $filename, "settings.txt" | Remove-Item;
Try {
	Invoke-WebRequest -ErrorAction Ignore "http://localhost:$Port/stop";
} Catch {}
Wait-Job $Job | Out-Null;
Remove-Job $Job | Out-Null;
$Env:tmp = $OldTmp;