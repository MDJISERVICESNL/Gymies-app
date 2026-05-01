-- Instagram handle op trainer storefront (voor feed/embed).
ALTER TABLE gymies_trainer_storefront
  ADD COLUMN instagram_handle VARCHAR(100) DEFAULT NULL
    COMMENT 'Instagram @handle zonder @, bijv. gymiesnl'
  AFTER video_pitch_url;
