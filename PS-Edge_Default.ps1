Param(
    [switch]$Init
)

Add-Type -AssemblyName PresentationFramework  # WPF 用
Add-Type -AssemblyName System.Windows.Forms   # Timer 用

$libWebView2Wpf    = (Join-Path $PSScriptRoot "lib\Microsoft.Web.WebView2.Wpf.dll")
$libWebView2Core   = (Join-Path $PSScriptRoot "lib\Microsoft.Web.WebView2.Core.dll")
$libWebview2Loader = (Join-Path $PSScriptRoot "lib\WebView2Loader.dll")

if ($Init) {
    # init.bat の実行時の動作(初期セットアップ用の処理)
    Write-Host "WebView2 ライブラリ取得を行います。既に取得している場合は一度削除し再取得します。"

    if (Test-Path "lib") {
        Write-Host "既に lib フォルダが存在する為削除します。"
        Remove-Item "lib" -Recurse
    }

    Write-Host "WebView2 パッケージを取得します。"
    Find-Package -Name  Microsoft.Web.WebView2 -Source https://www.nuget.org/api/v2 | Save-Package -Path $PSScriptRoot > $null
    $nugetFile    = Get-Item *.nupkg
    $nugetZipFile = $nugetFile.FullName + ".zip"

    Write-Host "WebView2 パッケージを展開します。"
    Rename-Item $nugetFile $nugetZipFile
    Expand-Archive $nugetZipFile > $null

    if (-not (Test-Path "lib")) {
        Write-Host "lib フォルダ(WebView2) フォルダの格納先を作成します。"
        New-Item -type Directory "lib" > $null
    }
    Write-Host "WebView2で利用するdllを配置します。"
    Copy-Item (Join-Path $nugetFile "\lib\net462\Microsoft.Web.WebView2.Core.dll") "lib"
    Copy-Item (Join-Path $nugetFile "\lib\net462\Microsoft.Web.WebView2.Wpf.dll") "lib"
    Copy-Item (Join-Path $nugetFile "\runtimes\win-x64\native\WebView2Loader.dll") "lib"

    Write-Host "不要になったnugetパッケージ類を削除します。"
    Remove-Item $nugetFile -Recurse
    Remove-Item $nugetZipFile

    if ((Test-Path $libWebView2Wpf) -and (Test-Path $libWebView2Core) -and (Test-Path $libWebview2Loader)) {
        Read-Host "取得に成功しました。boot.bat で PS-Edge の起動をご確認ください[Enter]"
        exit 0
    }
    else {
        Read-Host "取得に失敗しました[Enter]"
        exit 1
    }
}

<# WebView2 用アセンブリロード #>
[void][reflection.assembly]::LoadFile($libWebView2Wpf)
[void][reflection.assembly]::LoadFile($libWebView2Core)

<# XAML にて Window 構築 #>
[xml]$xaml  = (Get-Content (Join-Path $PSScriptRoot "ui01.xaml"))
$nodeReader = (New-Object System.XML.XmlNodeReader $xaml)
$window     = [Windows.Markup.XamlReader]::Load($nodeReader)

$webview  = $window.findName("webView")
$goButton = $window.findName("pageChange")
$urlText  = $window.findName("pageURL")
 
<# WebView2 の設定 #>
$webview.CreationProperties = New-Object 'Microsoft.Web.WebView2.Wpf.CoreWebView2CreationProperties'
$webview.CreationProperties.UserDataFolder = (Join-Path $PSScriptRoot "data")
$webview.Source = "file:///" + (Join-Path $PSScriptRoot "page01.html")
Set-Location $PSScriptRoot

# ここではPathの代入でIconを設定できるが、JS側からInvokeでPathを代入しようとすると「"値 "icon.ico" を型 "System.Windows.Media.ImageSource" に変換できません。」というエラーになってしまう。
$window.Icon = (Join-Path $PSScriptRoot "icon.ico")

<# Set EventListener #>
$goButton.add_Click({
    $webview.Source = $urlText.Text
})

$webview.add_SourceChanged({
    $urlText.Text = $webview.Source
})

$window.add_LocationChanged({
    param($event)
    Post2jsAsJson(@{act='Set'; target='window.position'; value=@{Left=$event.Left; Top=$event.Top}})
})

<# WebView2 Messaging #>
$webview.add_WebMessageReceived({
	param($webview, $message)
	$json = ($message.WebMessageAsJson | ConvertFrom-Json)
	
    $CallBack = {
        param($objArg = @{value=0; err=0})
        if(($json | get-member -name "numCallBack") -eq $false){return}
        $objArg.callBackId = $json.numCallBack
        Post2jsAsJson($objArg)
    }

	if(
        $json.act -eq 'Set' -or
        $json.act -eq 'Get' -or
        $json.act -eq 'GetMember'
    ){
        $target = $json.arg.target
        if($target[0] -eq 'window'){
            $currentObj = $window
        }else{
            return $CallBack.Invoke(@{err="対応していないオブジェクト・プロパティです。[$target[0]]"})
        }
        $last = $target.Length
        Try{
            For($i=1 ; $i -lt $last ; $i++){
                $name       = $json.arg.target[$i]
                if(($i+1) -eq $last){
                    if($json.act -eq 'Set'){
                        $currentObj.$name = $json.arg.value
                        return $CallBack.Invoke()
                    }
                    if($json.act -eq 'Get'){
                        return $CallBack.Invoke(@{value=$currentObj.$name})
                    }
                }
                $currentObj = $currentObj.$name
            }
            if($json.act -eq 'GetMember'){
                $res = $currentObj | Get-Member
                return $CallBack.Invoke(@{value=$res})
            }
        }Catch{
            return $CallBack.Invoke(
                @{err=
                    @{
                        key     = $target;
                        Message = $_.Exception.Message;
                    }
                }
            )
        }

        <# 以下は、argの中身が{window:{title:title}}のような形式だった時のコード。
            最終的に代入する値が常にスカラタイプならそれで良いが、オブジェクト型などを代入したい場合、以下では対応できない。
		if($json.arg | Get-Member -Name 'window'){
			$json.arg.window | Get-Member -MemberType NoteProperty | Select-Object Name | ForEach-Object -Process {
                $name         = $_.name # $_をそのままプロパティ名に使うと「Name(改行)----(改行)Title(改行)」のような文字列として解釈されてしまうため、一旦別変数に名前を抽出している。
				$value        = $json.arg.window.$name
                $window.$name = $value
			}
		}
        #>
        return $CallBack.Invoke()
	}
	
	if($json.act -eq 'Invoke'){
        $code = $json.arg.psCode
        try{
            # $res = $code.invoke($arg) # error stringにInvokeメソッドが無い
            $res = Invoke-Expression $code
            return $CallBack.Invoke(@{value=$res})
        }catch{
            return $CallBack.Invoke(@{err=$_.Exception.Message})
        }
	}
})

function Post2jsAsJson($obj){
    $webview.CoreWebView2.PostWebMessageAsJson(($obj | ConvertTo-Json))
}

# $window.Icon = (Join-Path $PSScriptRoot "icon.ico")

<# Window の表示 #>
[void]$window.ShowDialog()
# $window.Close()

<#
最後に「pause」を入れると、XAML画面を閉じた時に「PowerShellが動作を停止しました…」のメッセージが出なくなる。
しかし、それだとPSのプロセスが残り続けて、dataフォルダ内のファイルも使用中ロック状態になり、次に起動したプロセスからdataフォルダ内にアクセスできずフリーズしてしまう
pause

上と同時に以下を組み合わせてみたが、無意味だった。
$window.add_Close({
    exit
})

windowのCloseイベント発生時に上記がコールされているか確認するために以下を入れてみたが、表示されなかったのでコールされていなさそう。
[System.Windows.Forms.MessageBox]::Show("こんにちは！")
#>
