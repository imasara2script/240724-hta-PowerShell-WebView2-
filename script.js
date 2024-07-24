window.addEventListener('DOMContentLoaded', () => {
	document.querySelector('#submitTitle').addEventListener('click', async () => {
		await gate.window.setTitle(document.querySelector('#inputTitle').value)
        
        const newTitle = await gate.window.getTitle()
        confirm(newTitle)
	})
    
    gate.eventListener.add(
        'window.position',
        (value)=>{
		    document.querySelector('#xPos').innerText = value.Left
		    document.querySelector('#yPos').innerText = value.Top
        }
    )
})

invokeTest = async (psCode)=>{
    const res = await gate.PowerShell.invoke(psCode, 2)
    console.log(res)
}

gate = function(){
	// ブラウザ内で動作するJavaScriptと、OS側機能にアクセスできる外側(このverではPowerShell)の間のゲートという意味で
	// このオブジェクト名にした。…が、それだと「webサーバとクライアント」の間にも「ゲート」があって然るべき、という気もしてくるので
	// 「対OS」なことが分かりやすい名前が思いついたら変更するかも。
	
	const PowerShell = function(){
		const arrCallBack = []
		const send = (act, arg, callBack)=>{
			// 引数は階層構造のobjでもOK
			const objLetter = {act, arg}
			const postM = ()=>{ window.chrome.webview.postMessage(objLetter) }
			if(!callBack){ return postM() }
			
			let i = 0
			while(arrCallBack[i]){ i++ }
			arrCallBack[i] = callBack
			
			objLetter.numCallBack = i.toString()
			postM()
		}
		return {
			send,
			callBack : (numCallBack, value, err)=>{
			    // arrCallBack[i](value, err)のように実行しちゃうと、以下のような危険がありそうなので、一旦変数に入れる。
			    // arrCallBack[i] = function(){ this[0] = … }
			    const fun = arrCallBack[numCallBack]
                
			    // JSON.parseするかどうかはcallBack先に任せる。
			    fun(value, err)
			    
                // PS側エラーのハンドラーを個別のfunに書くのは面倒臭そうなので
                // ここでまとめて扱うようにしてみた。将来的には何らかの理由で変更の可能性あり。
                if(err){ throw err }
                
			    arrCallBack[numCallBack] = 0
		    },
			sendPromise : (act, arg)=>{
				return new Promise((resolve, reject)=>{
					send(act, arg, (v, e)=>{ e ? reject(e) : resolve(v) })
				})
			},
            invoke : async function(psCode           ){ return await this.sendPromise('invoke', {psCode}) },
            dir    : async function(path, isDirectory){ return await this.invoke(`dir -Path "${path}" ` + (isDirectory ? '-Directory' : '-File')) },
            start  : async function(cmd              ){ return await this.invoke('start '+cmd) } // フォルダを開く、ブラウザで任意のURLを開く、アプリを起動する、などに使用。
		}
	}()
    
    const FileSystem = function(){
        return {
            text : {
                read  : async (path)=>{ return (await PowerShell.invoke(`Get-Content "${path}" -Raw`)).value },
                write : async (path, value, isAdd, isSJIS)=>{
                    const escapedValue = (value+'').replace(/"/g,'`"')
                    return await PowerShell.invoke((isAdd ? 'Add' : 'Set') + `-Content "${path}" "${escapedValue}" -NoNewline` + (isSJIS ? ' -Encoding Ascii' : 'UTF8'))
                }
            }
        }
    }()
    
	return {
        PowerShell,
        FileSystem,
		window : {
			setTitle : async (title)=>{ return await PowerShell.sendPromise('set', {target:'window/title'.split('/'), value:title}) },
			getTitle : async (     )=>{ return await PowerShell.sendPromise('get', {target:'window/title'.split('/')             }) },
			getMember : async (key)=>{
                // keyの例：「position」「location」
                const target = ('window'+(key ? '/'+key : '')).split('/')
                const res = await PowerShell.sendPromise('getMember', {target})
                return res.split('\n ').sort()
            },
			setProperty : async (key, value)=>{ return await PowerShell.sendPromise('set', {target:('window.'+key).split('.'), value:value}) }
		},
        eventListener : function(){
            const objListener = {}
	        window.chrome.webview.addEventListener('message', function(event) {
                const objLetter = event.data
                if(objLetter.act=='Set'){
                    const arrFunc = objListener[objLetter.target]
                    if(!arrFunc){return}
                    arrFunc.forEach(func =>{ if(func){ func(objLetter.value, objLetter.err) }})
                    return
                }
                if(objLetter.callBackId !== undefined){
                    return PowerShell.callBack(objLetter.callBackId, objLetter.value, objLetter.err)
                }
                return
	        })
            
            return {
                add : (eventKey, func)=>{
                    if(!objListener[eventKey]){ objListener[eventKey] = [] }
                    const arr = objListener[eventKey]
                    let   num = 0
                    while(arr[num]){ num++ }
                    arr[num] = func
                    return num
                },
                del : (eventKey, num)=>{
                    objListener[eventKey][num] = 0
                }
            }
        }()
	}
}()
