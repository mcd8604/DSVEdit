class SpriteInfo
  class CreateCodeReadError < StandardError ; end
  
  attr_reader :gfx_file_pointers,
              :gfx_list_pointer,
              :palette_pointer,
              :palette_offset,
              :sprite_file_pointer,
              :skeleton_file,
              :sprite_file,
              :sprite,
              :gfx_pages,
              :ignore_part_gfx_page
  
  def initialize(gfx_file_pointers, palette_pointer, palette_offset, sprite_file_pointer, skeleton_file, fs, gfx_list_pointer: nil, ignore_part_gfx_page: false, hod_anim_list_ptr: nil, hod_anim_list_count: nil, hod_anim_ptrs: nil)
    if gfx_list_pointer
      @gfx_list_pointer = gfx_list_pointer
      @gfx_file_pointers = SpriteInfo.unpack_gfx_pointer_list(gfx_list_pointer, fs)
    else
      @gfx_file_pointers = gfx_file_pointers
    end
    @palette_pointer = palette_pointer
    @palette_offset = palette_offset
    @sprite_file_pointer = sprite_file_pointer
    @skeleton_file = skeleton_file
    @sprite_file = fs.assets_by_pointer[sprite_file_pointer]
    
    if @sprite_file_pointer.nil?
      @sprite = nil
    else
      @sprite = Sprite.new(
        sprite_file_pointer, fs,
        hod_anim_list_ptr: hod_anim_list_ptr, hod_anim_list_count: hod_anim_list_count, hod_anim_ptrs: hod_anim_ptrs
      )
    end
    
    @gfx_pages = @gfx_file_pointers.map do |gfx_pointer|
      GfxWrapper.new(gfx_pointer, fs)
    end
    
    @ignore_part_gfx_page = ignore_part_gfx_page
  end
  
  def gfx_list_pointer_or_gfx_file_pointers
    if gfx_list_pointer
      [gfx_list_pointer]
    else
      gfx_file_pointers
    end
  end
  
  def self.extract_gfx_and_palette_and_sprite_from_create_code(create_code_pointer, fs, overlay_to_load, reused_info, ptr_to_ptr_to_files_to_load=nil, update_code_pointer: nil)
    # This function attempts to find the enemy/object's gfx files, palette pointer, and sprite file.
    # It first looks in the list of files to load for that enemy/object (if given).
    # If any are missing after looking there, it then looks in the create code for pointers that look like they could be the pointers we want.
    
    #puts "create code: %08X" % create_code_pointer if create_code_pointer
    
    if overlay_to_load.is_a?(Integer)
      fs.load_overlay(overlay_to_load)
    elsif overlay_to_load.is_a?(Array)
      overlay_to_load.each do |overlay|
        fs.load_overlay(overlay)
      end
    end
    
    if GAME == "por"
      fs.load_overlay(4)
    end
    
    init_code_pointer      = reused_info[:init_code] || create_code_pointer
    update_code_pointer    = reused_info[:update_code] || update_code_pointer
    gfx_sheet_ptr_index    = reused_info[:gfx_sheet_ptr_index] || 0
    palette_offset         = reused_info[:palette_offset] || 0
    palette_list_ptr_index = reused_info[:palette_list_ptr_index] || 0
    sprite_ptr_index       = reused_info[:sprite_ptr_index] || 0
    ignore_files_to_load   = reused_info[:ignore_files_to_load] || false
    sprite_file_pointer    = reused_info[:sprite] || nil
    gfx_file_pointers      = reused_info[:gfx_files] || nil
    gfx_file_names         = reused_info[:gfx_file_names] || nil
    gfx_list_pointer       = reused_info[:gfx_wrapper] || nil
    palette_pointer        = reused_info[:palette] || nil
    ignore_part_gfx_page   = reused_info[:ignore_part_gfx_page] || false
    hod_anim_list_ptr      = reused_info[:hod_anim_list_ptr] || nil
    hod_anim_list_count    = reused_info[:hod_anim_list_count] || nil
    hod_anim_ptrs          = reused_info[:hod_anim_ptrs] || nil
    
    if gfx_file_pointers.nil? && gfx_file_names
      gfx_file_pointers = gfx_file_names.map do |gfx_file_name|
        fs.files_by_path[gfx_file_name][:asset_pointer]
      end
    end
    
    if reused_info[:no_sprite]
      sprite_file_pointer = nil
      if gfx_file_pointers && palette_pointer
        return SpriteInfo.new(
          gfx_file_pointers, palette_pointer, palette_offset,
          sprite_file_pointer, nil, fs
        )
      elsif gfx_list_pointer && palette_pointer
        gfx_file_pointers = unpack_gfx_pointer_list(gfx_list_pointer, fs)
        return SpriteInfo.new(
          gfx_file_pointers, palette_pointer, palette_offset,
          sprite_file_pointer, nil, fs
        )
      end
    end
    
    if sprite_file_pointer && gfx_file_pointers && palette_pointer
      return SpriteInfo.new(
        gfx_file_pointers, palette_pointer, palette_offset,
        sprite_file_pointer, nil, fs,
        ignore_part_gfx_page: ignore_part_gfx_page,
        hod_anim_list_ptr: hod_anim_list_ptr, hod_anim_list_count: hod_anim_list_count
      )
    elsif sprite_file_pointer && gfx_list_pointer && palette_pointer
      gfx_file_pointers = unpack_gfx_pointer_list(gfx_list_pointer, fs)
      return SpriteInfo.new(
        gfx_file_pointers, palette_pointer, palette_offset,
        sprite_file_pointer, nil, fs,
        ignore_part_gfx_page: ignore_part_gfx_page,
        hod_anim_list_ptr: hod_anim_list_ptr, hod_anim_list_count: hod_anim_list_count
      )
    end
    
    if init_code_pointer == -1
      raise CreateCodeReadError.new("This entity has no sprite.")
    end
    
    # Clear lowest two bits of init code pointer so it's aligned to 4 bytes.
    init_code_pointer = init_code_pointer & 0xFFFFFFFC
    
    gfx_files_to_load = []
    sprite_files_to_load = []
    skeleton_files_to_load = []
    palette_pointer_to_load = nil
    if ptr_to_ptr_to_files_to_load && !ignore_files_to_load
      pointer_to_start_of_file_index_list = fs.read(ptr_to_ptr_to_files_to_load, 4).unpack("V").first
      
      i = 0
      while true
        asset_index_or_palette_pointer, file_data_type = fs.read(pointer_to_start_of_file_index_list+i*8, 8).unpack("VV")
        
        if asset_index_or_palette_pointer == 0xFFFFFFFF
          # End of list.
          break
        end
        if file_data_type == 1 || file_data_type == 2
          asset_index = asset_index_or_palette_pointer
          file = fs.assets[asset_index]
          
          if file_data_type == 1
            gfx_files_to_load << GfxWrapper.new(file[:asset_pointer], fs)
          elsif file_data_type == 2
            if file[:file_path] =~ /\/so2?\/.+\.dat/
              sprite_files_to_load << file
            elsif file[:file_path] =~ /\/jnt\/.+\.jnt/
              skeleton_files_to_load << file
            elsif file[:file_path] =~ /\/sm\/.+\.nsbmd/
              # 3D model
            elsif file[:file_path] =~ /\/sm\/.+\.nsbtx/
              # 3D texture
            else
              puts "Unknown type of file to load: #{file.inspect}"
            end
          end
        elsif file_data_type == 3
          palette_pointer_to_load = asset_index_or_palette_pointer
        else
          raise CreateCodeReadError.new("Unknown file data type: #{file_data_type}")
        end
        
        i += 1
      end
      
      #if gfx_files_to_load.empty? && sprite_files_to_load.empty?
      #  raise CreateCodeReadError.new("No gfx files or sprite files to load found")
      #end
      #if gfx_files_to_load.empty?
      #  raise CreateCodeReadError.new("No gfx files to load found")
      #end
      #if sprite_files_to_load.empty?
      #  raise CreateCodeReadError.new("No sprite file to load found")
      #end
      #if palette_pointer_to_load.nil?
      #  raise CreateCodeReadError.new("No palette to load found")
      #end
      
      if gfx_files_to_load.length > 0 && sprite_files_to_load.length > 0 && palette_pointer_to_load
        gfx_file_pointers = gfx_files_to_load.map{|gfx| gfx.file[:asset_pointer]}
        sprite_file_pointer = sprite_files_to_load.first[:asset_pointer]
        
        return SpriteInfo.new(
          gfx_file_pointers, palette_pointer_to_load, palette_offset,
          sprite_file_pointer, skeleton_files_to_load.first, fs,
          ignore_part_gfx_page: ignore_part_gfx_page,
        hod_anim_list_ptr: hod_anim_list_ptr, hod_anim_list_count: hod_anim_list_count
        )
      end
    end
    
    
    
    possible_gfx_pointers = []
    gfx_page_pointer = nil
    list_of_gfx_page_pointers_wrapper_pointer = nil
    possible_palette_pointers = []
    possible_sprite_pointers = []
    
    data = fs.read(init_code_pointer, 4*1000, allow_length_to_exceed_end_of_file: true)
    
    data.unpack("V*").each_with_index do |word, i|
      if fs.is_pointer?(word)
        possible_gfx_pointers << word
        possible_palette_pointers << word
        possible_sprite_pointers << word
      end
    end
    
    if GAME == "hod" && hod_anim_ptrs.nil?
      # Try to automatically extract individual HoD animation pointers from the code.
      # Specifically, this detects cases where the game loads a single hardcoded animation pointer into r1, then calls EntitySetAnimation.
      # Note: A number of entities (e.g. Skeleton) instead will load a list pointer into r1, then load the one of the several animation pointers from that list with an index. These are not detected properly by this function (as the number of entries in the list can't be detected automatically).
      # TODO: This doesn't work with things like special object 28. It has multiple branches all leading to a single EntitySetAnimation call, but with different r1 values, so it misses some.
      
      update_code_pointer &= 0xFFFFFFFC
      
      hod_anim_ptrs = []
      funcs_to_check = [init_code_pointer, update_code_pointer]
      funcs_to_check.each do |func_pointer|
        last_seen_ldr_r1_value = nil
        sprite_animate_calls_seen = 0
        (func_pointer...func_pointer+2*1000).step(2) do |this_halfword_address|
          #puts "  %08X" % this_halfword_address
          this_halfword, next_halfword = fs.read(this_halfword_address, 4).unpack("vv")
          
          if (this_halfword & 0xFF00) == 0x4900
            # ldr r1, =(address)h
            offset = (this_halfword & 0x00FF) << 2
            dest_word_address = (this_halfword_address & ~3) + 4 + offset
            last_seen_ldr_r1_value = fs.read(dest_word_address, 4, allow_length_to_exceed_end_of_file: true).unpack("V").first
          elsif this_halfword == 0x4700
            # bx r0
            # Return. We reached the end of this function, so go on to the next function.
            break
          elsif (this_halfword & 0xF800) == 0xF000 && (next_halfword & 0xF800) == 0xF800
            # Function call.
            high_offset = this_halfword & 0x07FF
            low_offset  = next_halfword & 0x07FF
            offset = (high_offset << 12) | (low_offset << 1)
            signed_offset = offset
            if signed_offset & (1 << 22) != 0
              signed_offset = -(~offset & ((1 << 23) - 1)) # 23-bit signed integer
            end
            
            dest_function_address = this_halfword_address + 4 + signed_offset
            dest_function_address &= ~1 # Clear the lowest bit, which indicates this is a THUMB function being called.
            
            #puts "%08X %X %X %08X" % [this_halfword_address, offset, signed_offset, dest_function_address]
            if dest_function_address == ENTITY_SET_ANIMATION_FUNC_PTR
              if last_seen_ldr_r1_value.nil?
                puts "Unknown r1 value for EntitySetAnimation call at %08X" % this_halfword_address
                next
              end
              puts "%08X %08X" % [this_halfword_address, last_seen_ldr_r1_value]
              hod_anim_ptrs << last_seen_ldr_r1_value
            else
              last_seen_ldr_r1_value = nil
            end
          end
        end
      end
    end
    
    
    
    if possible_gfx_pointers.empty? && gfx_files_to_load.empty?
      raise CreateCodeReadError.new("Failed to find any possible sprite gfx pointers.")
    end
    
    valid_gfx_pointers = possible_gfx_pointers.select do |pointer|
      check_if_valid_gfx_wrapper_pointer(pointer, fs) || check_if_valid_gfx_list_pointer(pointer, fs)
    end
    possible_palette_pointers -= valid_gfx_pointers
    
    if gfx_file_pointers.nil? && gfx_files_to_load.empty?
      if gfx_list_pointer.nil?
        if valid_gfx_pointers.empty?
          raise CreateCodeReadError.new("Failed to find any valid sprite gfx pointers.")
        end
        if gfx_sheet_ptr_index >= valid_gfx_pointers.length
          raise CreateCodeReadError.new("Failed to find enough valid sprite gfx pointers to match the reused sprite gfx sheet index. (#{valid_gfx_pointers.length} found, #{gfx_sheet_ptr_index+1} needed.)")
        end
        
        gfx_list_or_file_pointer = valid_gfx_pointers[gfx_sheet_ptr_index]
      end
      
      if check_if_valid_gfx_list_pointer(gfx_list_or_file_pointer, fs)
        gfx_list_pointer = gfx_list_or_file_pointer
      else
        gfx_file_pointers = [gfx_list_or_file_pointer]
      end
    end
    possible_palette_pointers -= gfx_files_to_load.map{|gfx| gfx.gfx_pointer}
    
    
    
    if palette_pointer.nil?
      if possible_palette_pointers.empty?
        raise CreateCodeReadError.new("Failed to find any possible sprite palette pointers.")
      end
      
      valid_palette_pointers = possible_palette_pointers.select do |pointer|
        check_if_valid_palette_pointer(pointer, fs)
      end
      
      if valid_palette_pointers.empty?
        raise CreateCodeReadError.new("Failed to find any valid sprite palette pointers.")
      end
      if palette_list_ptr_index >= valid_palette_pointers.length
        raise CreateCodeReadError.new("Failed to find enough valid sprite palette pointers to match the reused sprite palette list index. (#{valid_palette_pointers.length} found, #{palette_list_ptr_index+1} needed.)")
      end
      
      palette_pointer = valid_palette_pointers[palette_list_ptr_index]
    end
    
    
    
    if sprite_files_to_load.empty? && sprite_file_pointer.nil?
      valid_sprite_pointers = possible_sprite_pointers.select do |pointer|
        check_if_valid_sprite_pointer(pointer, fs)
      end
      if valid_sprite_pointers.empty?
        raise CreateCodeReadError.new("Failed to find any valid sprite pointers.")
      end
      
      if sprite_ptr_index >= valid_sprite_pointers.length
        raise CreateCodeReadError.new("Failed to find enough valid sprite pointers to match the reused sprite index. (#{valid_sprite_pointers.length} found, #{sprite_ptr_index+1} needed.)")
      end
      sprite_file_pointer = valid_sprite_pointers[sprite_ptr_index]
      if sprite_file_pointer.nil?
        raise CreateCodeReadError.new("Failed to find any possible sprite pointers.")
      end
    end
    
    
    
    if ptr_to_ptr_to_files_to_load
      if gfx_files_to_load.length > 0
        gfx_file_pointers = gfx_files_to_load.map{|gfx| gfx.file[:asset_pointer]}
      end
      if palette_pointer_to_load
        palette_pointer = palette_pointer_to_load
      end
      if sprite_files_to_load.length > 0 && reused_info[:sprite].nil?
        sprite_file_pointer = sprite_files_to_load.first[:asset_pointer]
      end
      if skeleton_files_to_load.length > 0
        skeleton_file = skeleton_files_to_load.first
      end
    end
    
    return SpriteInfo.new(
      gfx_file_pointers, palette_pointer, palette_offset,
      sprite_file_pointer, skeleton_file, fs,
      gfx_list_pointer: gfx_list_pointer,
      ignore_part_gfx_page: ignore_part_gfx_page,
      hod_anim_list_ptr: hod_anim_list_ptr, hod_anim_list_count: hod_anim_list_count,
      hod_anim_ptrs: hod_anim_ptrs
    )
  end
  
  def self.unpack_gfx_pointer_list(gfx_list_pointer, fs)
    if SYSTEM == :nds
      data = fs.read(gfx_list_pointer+4, 4).unpack("V").first
      if fs.is_pointer?(data)
        _, _, number_of_gfx_pages, _ = fs.read(gfx_list_pointer, 4).unpack("C*")
        pointer_to_list_of_gfx_file_pointers = data
        
        gfx_file_pointers = fs.read(pointer_to_list_of_gfx_file_pointers, 4*number_of_gfx_pages).unpack("V*")
      else
        gfx_file_pointers = [gfx_list_pointer]
      end
      
      return gfx_file_pointers
    elsif SYSTEM == :gba
      header_vals = fs.read(gfx_list_pointer, 4).unpack("C*")
      is_single_gfx_page = [0, 1].include?(header_vals[0]) && header_vals[1] == 4 && header_vals[2] == 0x10 && header_vals[3] <= 0x10
      
      if is_single_gfx_page
        gfx_file_pointers = [gfx_list_pointer]
      else
        gfx_file_pointers = []
        i = 0
        while true
          pointer = fs.read(gfx_list_pointer+4+i*4, 4).unpack("V").first
          break unless fs.is_pointer?(pointer)
          gfx_file_pointers << pointer
          i += 1
        end
      end
      
      return gfx_file_pointers
    else
      return [gfx_list_pointer]
    end
  end
  
  def self.check_if_valid_gfx_wrapper_pointer(pointer, fs)
    if SYSTEM == :nds
      header_vals = fs.read(pointer, 4).unpack("C*") rescue return
      data = fs.read(pointer+4, 4).unpack("V").first
      if fs.is_pointer?(data)
        # This is probably a list of GFX pages, not a single one.
        false
      elsif data == 0x10
        # Just one GFX page, not a list
        header_vals[0] == 0 && (1..2).include?(header_vals[1]) && header_vals[2] == 0x10 && header_vals[3] == 0
      elsif data == 0x20
        # Canvas width is doubled.
        header_vals[0] == 0 && (1..2).include?(header_vals[1]) && header_vals[2] == 0x20 && header_vals[3] == 0
      else
        false
      end
    else
      header_vals = fs.read(pointer, 4).unpack("C*") rescue return
      data = fs.read(pointer+4, 4).unpack("V").first
      if fs.is_pointer?(data)
        is_single_compressed_gfx_page = header_vals[0] == 1 && header_vals[1] == 4 && header_vals[2] == 0x10 && header_vals[3] <= 0x10
        return is_single_compressed_gfx_page
      else
        is_single_uncompressed_gfx_page = header_vals[0] == 0 && header_vals[1] == 4 && header_vals[2] == 0x10 && header_vals[3] <= 0x10
        return is_single_uncompressed_gfx_page
      end
    end
  rescue NDSFileSystem::ConversionError => e
    return false
  end
  
  def self.check_if_valid_gfx_list_pointer(pointer, fs)
    if SYSTEM == :nds
      header_vals = fs.read(pointer, 4).unpack("C*") rescue return
      data = fs.read(pointer+4, 4).unpack("V").first
      if fs.is_pointer?(data)
        # There's a chance this might just be something that looks like a pointer (like palette data), so check to make sure it really is one.
        possible_gfx_page_pointer = fs.read(data, 4).unpack("V").first rescue return
        if fs.is_pointer?(possible_gfx_page_pointer)
          # List of GFX pages
          header_vals.all?{|val| val < 0x50} && (1..2).include?(header_vals[1])
        else
          false
        end
      else
        false
      end
    else
      header_vals = fs.read(pointer, 4).unpack("C*") rescue return
      data = fs.read(pointer+4, 4).unpack("V").first
      if fs.is_pointer?(data)
        is_gfx_list = (2..3).include?(header_vals[0]) && (1..0xF).include?(header_vals[1]) && [2, 4].include?(header_vals[2]) && (1..2).include?(header_vals[3])
        return is_gfx_list
      else
        false
      end
    end
  rescue NDSFileSystem::ConversionError => e
    return false
  end
  
  def self.check_if_valid_palette_pointer(pointer, fs)
    if SYSTEM == :nds
      header_vals = fs.read(pointer, 4).unpack("C*") rescue return
      header_vals[0] == 0 && header_vals[1] == 1 && header_vals[2] > 0 && header_vals [3] == 0
    else
      header_vals = fs.read(pointer, 4).unpack("C*") rescue return
      header_vals[0] == 0 && header_vals[1] == 4 && header_vals[2] > 0 && header_vals [3] == 0
    end
  end
  
  def self.check_if_valid_sprite_pointer(pointer, fs)
    if SYSTEM == :nds
      if fs.all_sprite_pointers.include?(pointer)
        true
      else
        # Check if any of the overlay files containing sprite data include this pointer.
        OVERLAY_FILES_WITH_SPRITE_DATA.any? do |overlay_id|
          overlay = fs.overlays[overlay_id]
          range = (overlay[:ram_start_offset]..overlay[:ram_start_offset]+overlay[:size]-1)
          range.include?(pointer)
        end
      end
    else
      num_frames, num_anims, frames_ptr, anims_ptr = fs.read(pointer, 12).unpack("vvVV") rescue return
      return false if !fs.is_pointer?(frames_ptr)
      return false if num_frames == 0
      return false if num_anims > 0 && anims_ptr == 0
      return false if num_frames >= 0x100 # TODO
      return false if num_anims >= 0x100 # TODO
      return false if frames_ptr % 4 != 0
      return false if anims_ptr % 4 != 0
      return false if pointer < 0x08200000 && GAME == "aos" # HACK TODO
      return true
    end
  end
end
