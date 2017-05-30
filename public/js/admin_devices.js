$( document ).ready(function() {
  $('.enabled-sensors-switch').click(function(){
    $.ajax({
      url: '/devices/sensors/toggle',
      type: 'POST',
      success: function(result) {
        console.log(result);
        error = JSON.parse(result).error;
        if (error != null){
          location.reload();
        }
      }
    });
  });

  $('.enabled-camera-switch').click(function(){
    $.ajax({
      url: '/devices/camera/toggle',
      type: 'POST',
      success: function(result) {
        console.log(result);
        error = JSON.parse(result).error;
        if (error != null){
          location.reload();
        }
      }
    });
  });
});