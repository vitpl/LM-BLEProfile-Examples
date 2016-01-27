return { 
  manufacturer = 'BeeWi',
  description = 'Smart LED Color Bulb',
  default_name = 'BeeWi Bulb',
  version = 1,  
  --список объектов - групповых адресов, которые будут созданы при настройке устройства  
  objects = { 
	--включение/выключение, управляющий объект
    {
      id = 'power',
      name = 'Power',
      datatype = dt.bool,
	  write_only = true
    },
	--текущий статус включена ли лампа 
    {
      id = 'power_status',
      name = 'Power status',
      datatype = dt.bool,
	  read_only = true
    },
	--установки температуры цвета 
    {
      id = 'white',
      name = 'Color temperature',
      datatype = dt.scale,
	  write_only = true
    },
	--статус, установленная температура цвета 
    {
      id = 'white_status',
      name = 'Color temperature status',
      datatype = dt.scale,
	  read_only = true
    },
	--установка цвета RGB 
    {
      id = 'color',
      name = 'RGB color',
      datatype = dt.rgb,
	  write_only = true
    },
	--статус, установленный цвет RGB 
    {
      id = 'color_status',
      name = 'RGB color status',
      datatype = dt.rgb,
	  read_only = true
    },
	--установка яркости света 
    {
      id = 'brightness',
      name = 'Brightness',
      datatype = dt.scale,
	  write_only = true
    },
	--статус, установленная яркость света 
    {
      id = 'brightness_status',
      name = 'Brightness Status',
      datatype = dt.scale,
	  read_only = true
    }
  },
  
  --опрос лампы, выполняется с периодичностью, указанной в настройках устройства 
	read = function(device)
		local values = {}
		--подключение к устройству 
		local res, sock, err  = device.profile._connect(device)

		local status
		if res and sock then
			--чтение значений из конретных адресов (handle) 
		  local value_0x24 = ble.sockreadhnd(sock, 0x24) or ''
		  if (#value_0x24 == 5) then   
			status = true
			if (value_0x24:byte(1) == 0) then
			  values.power_status = false
			elseif (value_0x24:byte(1) == 1) then
			  values.power_status = true
			end
			values.white_status = (bit.band(value_0x24:byte(2), 15)-1) * 10 
			values.brightness_status = ((bit.rshift(bit.band(value_0x24:byte(2), 240), 4)-1)) * 10 
			values.color_status = bit.lshift(bit.band(value_0x24:byte(3),0xFF),16) + bit.lshift(bit.band(value_0x24:byte(4),0xFF),8) + bit.band(value_0x24:byte(5),0xFF)
		  end
		end

		if not status then 
			--отключение от устройства 
			device.profile._disconnect(device) 
		end 

		--возвращается 
		--status - Логическое, удалось ли подключится к устройству 
		--values - таблица со значениями, при этом ключи в таблице должны совпадать с 
		--id, указанными в списке объектов. Все значения, возвращенные функцией, будут записаны 
		--в соотвествующие групповые адреса 
		return status, values
	end,
	
	--запись значений (отправка команд) к устройству
	--функция выполняется, при записи значений 
	--в групповые адреса (указанные в настройках) контроллера 
	write = function(device, object, value)
		--подключение к лампе 
		local res, sock, err  = device.profile._connect(device)
		
		local res2 = 1
		if res and sock then
			--проверка в какой адрес было записано значение и запись нового значения по конкретному адресу на лампу 
			if (object.id == 'power') then
				if (value == true) then
				  res2, err = ble.sockwritecmd(sock, 0x21, 0x55, 0x10, 0x01, 0x0D, 0x0A)
				end
				if (value == false) then
				  res2, err = ble.sockwritecmd(sock, 0x21, 0x55, 0x10, 0x00, 0x0D, 0x0A)
				end

			elseif (object.id == 'color') then
				red = bit.band(bit.rshift(value, 16), 0xFF)
				green = bit.band(bit.rshift(value, 8), 0xFF)
				blue = bit.band(value, 0xFF)
				res2, err = ble.sockwritecmd(sock, 0x21, 0x55, 0x13, red, green, blue, 0x0D, 0x0A)

			elseif (object.id == 'white') then
				value =  math.floor(value / 10 +0.5)
				ble.sockwritecmd(sock, 0x21, 0x55, 0x14, 0xFF, 0xFF, 0xFF, 0x0D, 0x0A)
				res2, err = ble.sockwritecmd(sock, 0x21, 0x55, 0x11, (value)+1, 0x0D, 0x0A)

			elseif (object.id == 'brightness') then
				value =  math.floor(value / 10 +0.5)
				res2, err = ble.sockwritecmd(sock, 0x21, 0x55, 0x12, (value)+1, 0x0D, 0x0A)
			end 
		end 

		if res2<=0 then 
			device.profile._disconnect(device) 
		end 
	end,

	--вспомогательный метод, подключение к лампе 
	--в случае с лампой соединение контроллером устанавливается один раз 
	--и переподключение осуществляется только в случае потери соединения 
	--открытый sock Хранится в таблице device 
	_connect = function(device) 
		local res, err = true, nil 
		
		local sock = device.sock 
		
		if not sock or not ble.check(sock) then 
			if sock then 
				ble.close(sock) 
			end 
			
			sock = ble.sock() 
			ble.settimeout(sock, 30) 
			local i = 1 
			res, err = ble.connect(sock, device.mac) 
			while not res and i<10 do  --не всегда коннектится с первой попытки 
				os.sleep(0.5) 
				res, err = ble.connect(sock, device.mac)
				i = i + 1 
			end 
			
			if not res then 
				ble.close(sock) 
				sock = nil 
			end 
				
			device.sock = sock  --сохраняем sock в таблице device 
		end 
		
		return res, sock, err 
	end,

	--отключение соединения 
	_disconnect = function(device) 
		local sock = device.sock 
		if sock then 
			ble.close(sock) 	
		end 
		device.sock = nil 
	end 
}
