window.onload = function onLoad() {
    var countElm = $('.total_count'),
    countSpeed = 20;
 
    countElm.each(function(){
        var self = $(this),
        countMax = self.attr('data-num'),
        thisCount = self.text(),
        countTimer;
        const countUp = parseInt(self.attr('data-num')/1000) + 1;
 
        function timer(){
            countTimer = setInterval(function(){
                var countNext = Number(thisCount);
                thisCount = Number(thisCount) + countUp;
 
                if(countNext >= countMax){
                    clearInterval(countTimer);
                    countNext = countMax;
                }
                self.text(countNext);
            },countSpeed);
        }
        timer();
    });
 
};

