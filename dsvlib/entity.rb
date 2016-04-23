class Entity
  attr_reader :room,
              :fs
  attr_accessor :entity_ram_pointer,
                :x_pos,
                :y_pos,
                :byte_5,
                :type,
                :subtype,
                :byte_8,
                :var_a,
                :var_b
  
  def initialize(room, fs)
    @room = room
    @fs = fs
  end
  
  def read_from_rom(entity_ram_pointer)
    @entity_ram_pointer = entity_ram_pointer
    
    @x_pos, @y_pos = fs.read(entity_ram_pointer,4).unpack("v*")
    @byte_5, @type, @subtype, @byte_8 = fs.read(entity_ram_pointer+4,4).unpack("C*")
    @var_a, @var_b = fs.read(entity_ram_pointer+8,4).unpack("v*")
    
    return self
  end
  
  def write_to_rom
    room.sector.load_necessary_overlay()
    
    if entity_ram_pointer.nil?
      raise "Can't save an entity that doesn't have a pointer"
    end
    
    fs.write(entity_ram_pointer, [x_pos, y_pos].pack("v*"))
    fs.write(entity_ram_pointer+4, [byte_5, type, subtype, byte_8].pack("C*"))
    fs.write(entity_ram_pointer+8, [var_a, var_b].pack("v*"))
  end
  
  def is_enemy?
    type == 0x01
  end
  
  def is_common_enemy?
    is_enemy? && COMMON_ENEMY_IDS.include?(subtype)
  end
  
  def is_boss?
    is_enemy? && BOSS_IDS.include?(subtype)
  end
  
  def is_pickup?
    raise NotImplementedError
  end
end